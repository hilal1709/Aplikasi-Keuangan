import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:postgrest/postgrest.dart';

import '../providers.dart';
import '../sync/sync_providers.dart';
import 'neon.dart';
import '../../services/realtime.dart';

class Household {
  const Household({required this.id, required this.name, required this.inviteCode});
  final String id;
  final String name;
  final String inviteCode;

  factory Household.fromJson(Map<String, dynamic> j) =>
      Household(id: j['id'] as String, name: j['name'] as String, inviteCode: j['invite_code'] as String);
}

/// Rumah tangga yang tersimpan di server untuk akun ini, beserta jumlah transaksinya
/// (supaya pengguna bisa mengenali mana yang berisi datanya).
class HouseholdSummary {
  const HouseholdSummary(this.household, {required this.role, required this.transactions});
  final Household household;
  final String role;
  final int transactions;
}

/// Operasi rumah tangga lewat fungsi RPC di Postgres (lihat db/migrations).
class HouseholdService {
  HouseholdService(this.ref);
  final Ref ref;

  String get _uid => Neon.auth.currentUser!.id;

  Future<void> saveProfile(String displayName, {String? avatar}) async {
    await (await Neon.db()).from('profiles').upsert({
      'id': _uid,
      'display_name': displayName,
      'avatar': avatar ?? ref.read(avatarKeyProvider),
    });
  }

  Future<Household?> current() async {
    final hid = ref.read(householdIdProvider);
    if (hid == null || Neon.auth.currentUser == null) return null;
    final row = await (await Neon.db()).from('households').select().eq('id', hid).maybeSingle();
    return row == null ? null : Household.fromJson(row);
  }

  /// Semua rumah tangga yang pernah diikuti akun ini, yang paling banyak datanya dulu.
  /// Dipakai untuk memulihkan data setelah install ulang / ganti HP.
  Future<List<HouseholdSummary>> mine() async {
    if (Neon.auth.currentUser == null) return const [];
    final client = await Neon.db();
    final List<dynamic> rows = await client.from('household_members').select('household_id, role').eq('user_id', _uid);
    if (rows.isEmpty) return const [];
    final roles = {for (final r in rows.cast<Map<String, dynamic>>()) r['household_id'] as String: r['role'] as String};
    final List<dynamic> hs = await client.from('households').select().inFilter('id', roles.keys.toList());
    final out = await Future.wait(hs.cast<Map<String, dynamic>>().map((raw) async {
      final h = Household.fromJson(raw);
      final res = await client.from('transactions').select('id').eq('household_id', h.id).isFilter('deleted_at', null).count(CountOption.exact);
      return HouseholdSummary(h, role: roles[h.id] ?? 'member', transactions: res.count);
    }));
    return out..sort((a, b) => b.transactions.compareTo(a.transactions));
  }

  /// Menyambungkan perangkat ini kembali ke rumah tangga yang sudah ada di server
  /// (install ulang, ganti HP, atau pindah dari rumah tangga lain milik akun yang sama).
  Future<void> restore(Household h) async {
    final engine = ref.read(syncEngineProvider)!;
    final prev = ref.read(householdIdProvider);
    if (prev != null && prev != h.id) await engine.forgetHousehold(prev);
    await ref.read(householdIdProvider.notifier).set(h.id);
    await engine.clearMarks(h.id);
    await engine.run(h.id);
    // Kategori bawaan dari onboarding digabung ke milik akun, dompet onboarding yang belum
    // dipakai dibuang; catatan lain yang sempat dibuat sebelum login ikut dipindahkan.
    await engine.mergeSeedCategories(h.id);
    await engine.discardUnusedLocalWallets();
    await engine.adoptLocalData(h.id, _uid);
    await engine.run(h.id);
  }

  /// Setelah login di perangkat yang belum tersambung: bila akun punya tepat satu
  /// rumah tangga, langsung dipulihkan. Mengembalikan yang dipulihkan (atau null).
  Future<HouseholdSummary?> restoreIfSingle() async {
    if (ref.read(householdIdProvider) != null) return null;
    final list = await mine();
    if (list.length != 1) return null;
    await restore(list.first.household);
    ref.invalidate(currentHouseholdProvider);
    return list.first;
  }

  /// Membuat rumah tangga baru; seluruh data lokal ikut dipindahkan ke sana.
  Future<Household> create(String name) async {
    final res = await (await Neon.db()).rpc('create_household', params: {'p_name': name});
    final h = Household.fromJson(Map<String, dynamic>.from(res as Map));
    await ref.read(householdIdProvider.notifier).set(h.id);
    final engine = ref.read(syncEngineProvider)!;
    await engine.adoptLocalData(h.id, _uid);
    await engine.run(h.id);
    return h;
  }

  /// Bergabung dengan kode undangan. Data rumah tangga ditarik dulu,
  /// kategori bawaan yang sama digabung, baru data lokal ikut dikirim.
  Future<Household> join(String code) async {
    final res = await (await Neon.db()).rpc('join_household', params: {'p_code': code.trim().toUpperCase()});
    final h = Household.fromJson(Map<String, dynamic>.from(res as Map));
    await ref.read(householdIdProvider.notifier).set(h.id);
    final engine = ref.read(syncEngineProvider)!;
    await engine.run(h.id);
    await engine.mergeSeedCategories(h.id);
    await engine.adoptLocalData(h.id, _uid);
    await engine.run(h.id);
    return h;
  }

  /// Keluar dari rumah tangga yang sedang dipakai. Perubahan tertunda dikirim dulu,
  /// lalu salinan lokalnya dilepas dari HP ini. Mengembalikan true bila rumah tangga
  /// ikut terhapus karena kamu anggota terakhir.
  Future<bool> leave() async {
    final hid = ref.read(householdIdProvider)!;
    final engine = ref.read(syncEngineProvider)!;
    await engine.push(hid);
    final res = await (await Neon.db()).rpc('leave_household', params: {'p_household': hid});
    await detach(hid);
    return res == 'deleted';
  }

  /// Pemilik mengeluarkan anggota lain; daftar anggota langsung ditarik ulang.
  Future<void> removeMember(String userId) async {
    final hid = ref.read(householdIdProvider)!;
    await (await Neon.db()).rpc('remove_member', params: {'p_household': hid, 'p_user': userId});
    final engine = ref.read(syncEngineProvider)!;
    engine.client = await Neon.db();
    await engine.pullMembers(hid);
  }

  /// Memutus HP ini dari rumah tangga yang aksesnya sudah tidak ada lagi
  /// (keluar sendiri atau dikeluarkan pemilik).
  Future<void> detach(String hid) async {
    await ref.read(syncEngineProvider)!.forgetHousehold(hid, pushFirst: false, force: true);
    await ref.read(householdIdProvider.notifier).set(null);
    ref.invalidate(currentHouseholdProvider);
  }

  Future<String> regenerateCode() async {
    final hid = ref.read(householdIdProvider)!;
    final res = await (await Neon.db()).rpc('regenerate_invite_code', params: {'p_household': hid});
    return res as String;
  }

  Future<void> signOut() async {
    await ref.read(realtimeProvider.notifier).unregisterPush();
    await Neon.auth.signOut();
  }
}

final householdServiceProvider = Provider<HouseholdService>(HouseholdService.new);

/// Rumah tangga milik akun yang sedang login (dari server).
final myHouseholdsProvider = FutureProvider.autoDispose<List<HouseholdSummary>>((ref) {
  ref.watch(authUserProvider);
  ref.watch(householdIdProvider);
  return ref.read(householdServiceProvider).mine();
});

final currentHouseholdProvider = FutureProvider<Household?>((ref) {
  ref.watch(householdIdProvider);
  ref.watch(authUserProvider);
  return ref.read(householdServiceProvider).current();
});
