import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final currentHouseholdProvider = FutureProvider<Household?>((ref) {
  ref.watch(householdIdProvider);
  ref.watch(authUserProvider);
  return ref.read(householdServiceProvider).current();
});
