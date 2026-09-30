import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgrest/postgrest.dart';

import '../remote/neon.dart';

import '../local/database.dart';

class SyncReport {
  const SyncReport(this.pushed, this.newTx, [this.changes = const {}]);
  final int pushed;
  final List<TxEntry> newTx;

  /// Baris yang baru terkirim & boleh dilihat anggota lain, per tabel remote
  /// (format Postgres). Ikut dikirim lewat Pusher supaya HP pasangan bisa
  /// langsung menampilkannya tanpa menunggu menarik dari Neon.
  final Map<String, List<Map<String, dynamic>>> changes;
}

/// Deskripsi satu tabel yang disinkronkan.
class SyncSpec {
  const SyncSpec({required this.local, required this.remote, required this.fromJson, required this.dateFields});
  final TableInfo<Table, dynamic> local;
  final String remote;
  final Insertable<dynamic> Function(Map<String, dynamic>) fromJson;

  /// Nama field (camelCase) bertipe DateTime.
  final Set<String> dateFields;
}

const _base = {'createdAt', 'updatedAt', 'deletedAt'};

List<SyncSpec> syncSpecs(AppDatabase db) => [
      // Urutan penting: induk dulu (dompet, kategori) baru anak (transaksi, dll).
      SyncSpec(local: db.wallets, remote: 'wallets', fromJson: Wallet.fromJson, dateFields: _base),
      SyncSpec(local: db.categories, remote: 'categories', fromJson: Category.fromJson, dateFields: _base),
      SyncSpec(local: db.goals, remote: 'goals', fromJson: Goal.fromJson, dateFields: {..._base, 'deadline', 'achievedAt'}),
      SyncSpec(local: db.recurringRules, remote: 'recurring_rules', fromJson: RecurringRule.fromJson, dateFields: {..._base, 'nextRun'}),
      SyncSpec(local: db.bills, remote: 'bills', fromJson: Bill.fromJson, dateFields: {..._base, 'dueDate', 'paidAt'}),
      SyncSpec(local: db.txEntries, remote: 'transactions', fromJson: TxEntry.fromJson, dateFields: {..._base, 'occurredAt'}),
      SyncSpec(local: db.budgets, remote: 'budgets', fromJson: Budget.fromJson, dateFields: {..._base, 'month'}),
      SyncSpec(
        local: db.goalContributions,
        remote: 'goal_contributions',
        fromJson: GoalContribution.fromJson,
        dateFields: {..._base, 'occurredAt'},
      ),
    ];

String _snake(String s) => s.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
String _camel(String s) => s.replaceAllMapped(RegExp('_([a-z])'), (m) => m[1]!.toUpperCase());

/// Sinkronisasi dua arah dengan Neon Data API:
/// - push: baris `dirty` di-upsert ke Postgres, lalu ditandai bersih
///   (hanya jika tidak diubah lagi selama proses kirim);
/// - pull: baris dengan `server_updated_at` lebih baru dari tanda terakhir,
///   dengan aturan last-write-wins berdasarkan `updated_at`.
class SyncEngine {
  SyncEngine(this.db, this.prefs);
  final AppDatabase db;
  final SharedPreferences prefs;

  /// Klien Data API dengan JWT segar untuk satu putaran sinkron.
  late PostgrestClient client;

  /// Menjalankan satu putaran sinkron penuh: kirim lalu tarik.
  Future<SyncReport> run(String householdId) async {
    final report = await push(householdId);
    await pull(householdId);
    return report;
  }

  /// Mengirim semua baris `dirty` ke Neon (semua tabel paralel).
  Future<SyncReport> push(String householdId) async {
    client = await Neon.db();
    final specs = syncSpecs(db);
    final pushedPerSpec = await Future.wait(specs.map((s) => _push(s, householdId)));
    var pushed = 0;
    final newTx = <TxEntry>[];
    final changes = <String, List<Map<String, dynamic>>>{};
    for (final (i, s) in specs.indexed) {
      final rows = pushedPerSpec[i];
      if (rows.isEmpty) continue;
      pushed += rows.length;
      if (identical(s.local, db.txEntries)) {
        newTx.addAll(rows.cast<TxEntry>().where((t) => t.deletedAt == null && t.updatedAt.difference(t.createdAt).inSeconds.abs() < 5));
      }
      final visible = <Map<String, dynamic>>[];
      for (final d in rows) {
        if (await _visibleToOthers(s, d)) visible.add(_toRemote(s, d.toJson()));
      }
      changes[s.remote] = visible;
    }
    return SyncReport(pushed, newTx, changes);
  }

  /// Menarik perubahan dari Neon. Semua tabel diminta paralel (hemat waktu karena
  /// server jauh), lalu diterapkan berurutan induk dulu baru anak.
  /// [tables] membatasi ke tabel tertentu (nama remote), mis. dari sinyal realtime.
  Future<void> pull(String householdId, {Set<String>? tables}) async {
    client = await Neon.db();
    final specs = syncSpecs(db).where((s) => tables == null || tables.contains(s.remote)).toList();
    final fetched = await Future.wait([
      for (final s in specs) _fetch(s, householdId),
      if (tables == null) pullMembers(householdId).then((_) => const <Map<String, dynamic>>[]),
    ]);
    for (final (i, s) in specs.indexed) {
      final rows = fetched[i];
      if (rows.isEmpty) continue;
      await _apply(s, rows);
      await prefs.setString(_markKey(s, householdId), rows.last['server_updated_at'] as String);
    }
  }

  /// Menerapkan baris yang datang lewat Pusher (format Postgres) dengan aturan
  /// last-write-wins yang sama. Tanda tarik tidak dimajukan, jadi tarikan
  /// berikutnya tetap mengambil versi resmi dari server.
  Future<int> applyChanges(Map<String, dynamic> changes, String householdId) async {
    var n = 0;
    for (final s in syncSpecs(db)) {
      final raw = changes[s.remote];
      if (raw is! List || raw.isEmpty) continue;
      final rows = raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).where((m) => m['household_id'] == householdId).toList();
      await _apply(s, rows);
      n += rows.length;
    }
    return n;
  }

  String _markKey(SyncSpec s, String householdId) => 'sync_mark_${s.remote}_$householdId';

  /// Meniru aturan RLS di sisi pengirim: baris pribadi tidak ikut disiarkan.
  Future<bool> _visibleToOthers(SyncSpec s, DataClass d) async {
    Future<bool> walletShared(String? id) async {
      if (id == null) return true;
      final w = await (db.select(db.wallets)..where((x) => x.id.equals(id))).getSingleOrNull();
      return w?.isShared ?? false;
    }

    return switch (d) {
      Wallet w => w.isShared,
      TxEntry t => await walletShared(t.walletId),
      Goal g => g.isShared,
      GoalContribution c => (await (db.select(db.goals)..where((x) => x.id.equals(c.goalId))).getSingleOrNull())?.isShared ?? false,
      Budget b => b.isShared,
      RecurringRule r => await walletShared(r.walletId),
      Bill b => await walletShared(b.walletId),
      _ => true,
    };
  }

  Stream<int> watchPending() {
    final specs = syncSpecs(db);
    final sql = specs.map((s) => 'SELECT COUNT(*) AS c FROM ${s.local.actualTableName} WHERE dirty = 1').join(' UNION ALL ');
    return db
        .customSelect('SELECT SUM(c) AS n FROM ($sql)', readsFrom: specs.map((s) => s.local).toSet())
        .watchSingle()
        .map((r) => r.read<int?>('n') ?? 0);
  }

  Future<List<DataClass>> _push(SyncSpec s, String householdId) async {
    final table = s.local.actualTableName;
    final rows = await db.customSelect('SELECT * FROM $table WHERE dirty = 1 AND household_id = ?', variables: [
      Variable.withString(householdId),
    ]).get();
    if (rows.isEmpty) return const [];

    final dataRows = rows.map((r) => s.local.map(r.data) as DataClass).toList();
    for (var i = 0; i < dataRows.length; i += 400) {
      final chunk = dataRows.sublist(i, i + 400 > dataRows.length ? dataRows.length : i + 400);
      final payload = chunk.map((d) => _toRemote(s, d.toJson())).toList();
      await client.from(s.remote).upsert(payload);
      for (final d in chunk) {
        final json = d.toJson();
        await db.customUpdate(
          'UPDATE $table SET dirty = 0 WHERE id = ? AND updated_at = ?',
          variables: [
            Variable.withString(json['id'] as String),
            Variable.withDateTime(DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)),
          ],
          updates: {s.local},
        );
      }
    }
      return dataRows;
  }

  Future<List<Map<String, dynamic>>> _fetch(SyncSpec s, String householdId) async {
    var mark = prefs.getString(_markKey(s, householdId)) ?? '1970-01-01T00:00:00Z';
    final all = <Map<String, dynamic>>[];
    while (true) {
      final List<dynamic> rows = await client
          .from(s.remote)
          .select()
          .eq('household_id', householdId)
          .gt('server_updated_at', mark)
          .order('server_updated_at')
          .limit(1000);
      all.addAll(rows.cast<Map<String, dynamic>>());
      if (rows.length < 1000) break;
      mark = (rows.last as Map<String, dynamic>)['server_updated_at'] as String;
    }
    return all;
  }

  Future<void> _apply(SyncSpec s, List<Map<String, dynamic>> rows) async {
    await db.transaction(() async {
      for (final raw in rows) {
        final json = _fromRemote(s, raw);
        final local = await db.customSelect(
          'SELECT dirty, updated_at FROM ${s.local.actualTableName} WHERE id = ?',
          variables: [Variable.withString(json['id'] as String)],
        ).getSingleOrNull();
        final remoteUpdated = DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int);
        if (local != null) {
          final localUpdated = local.read<DateTime>('updated_at');
          // Perubahan lokal yang belum terkirim menang bila lebih baru.
          if (local.read<bool>('dirty') && localUpdated.isAfter(remoteUpdated)) continue;
        }
        await db.into(s.local).insertOnConflictUpdate(s.fromJson(json));
      }
    });
  }

  Future<void> pullMembers(String householdId) async {
    final List<dynamic> rows = await client.from('household_member_profiles').select().eq('household_id', householdId);
    await db.transaction(() async {
      await (db.delete(db.members)..where((m) => m.householdId.equals(householdId))).go();
      for (final r in rows.cast<Map<String, dynamic>>()) {
        await db.into(db.members).insertOnConflictUpdate(MembersCompanion.insert(
              userId: r['user_id'] as String,
              householdId: householdId,
              displayName: (r['display_name'] as String?)?.trim().isNotEmpty == true ? r['display_name'] as String : 'Anggota',
              role: r['role'] as String,
              color: Value((r['color'] as int?) ?? 0xFFFE64A3),
              avatar: Value(r['avatar'] as String?),
            ));
      }
    });
  }

  Map<String, dynamic> _toRemote(SyncSpec s, Map<String, dynamic> json) {
    final out = <String, dynamic>{};
    json.forEach((k, v) {
      if (k == 'dirty') return;
      if (s.dateFields.contains(k) && v != null) {
        v = DateTime.fromMillisecondsSinceEpoch(v as int).toUtc().toIso8601String();
      }
      out[_snake(k)] = v;
    });
    return out;
  }

  Map<String, dynamic> _fromRemote(SyncSpec s, Map<String, dynamic> raw) {
    final out = <String, dynamic>{'dirty': false};
    raw.forEach((k, v) {
      if (k == 'server_updated_at') return;
      // Kolom yang belum dikenal versi aplikasi ini diabaikan.
      final c = _camel(k);
      if (s.dateFields.contains(c) && v != null) {
        v = DateTime.parse(v as String).toLocal().millisecondsSinceEpoch;
      }
      out[c] = v;
    });
    return out;
  }

  /// Melepas rumah tangga dari perangkat ini: perubahan yang belum terkirim dikirim dulu,
  /// lalu salinan lokalnya dihapus (data di server tetap utuh) dan tanda tarik direset.
  /// [pushFirst] false & [force] true dipakai setelah keluar/dikeluarkan: akses ke server
  /// sudah tidak ada, jadi semua salinan lokal rumah tangga itu dibuang.
  Future<void> forgetHousehold(String householdId, {bool pushFirst = true, bool force = false}) async {
    if (pushFirst) await push(householdId);
    await db.transaction(() async {
      // Anak dulu baru induk (kebalikan urutan sinkron).
      for (final s in syncSpecs(db).reversed) {
        await db.customUpdate(
          'DELETE FROM ${s.local.actualTableName} WHERE household_id = ?${force ? '' : ' AND dirty = 0'}',
          variables: [Variable.withString(householdId)],
          updates: {s.local},
          updateKind: UpdateKind.delete,
        );
      }
      await (db.delete(db.members)..where((m) => m.householdId.equals(householdId))).go();
    });
    await clearMarks(householdId);
  }

  /// Apakah [userId] masih tercatat sebagai anggota (menurut daftar anggota yang terakhir ditarik).
  /// Setelah dikeluarkan, RLS membuat daftar anggota kosong bagi orang itu.
  Future<bool> isMember(String householdId, String userId) async {
    final row = await (db.select(db.members)..where((m) => m.householdId.equals(householdId) & m.userId.equals(userId))).getSingleOrNull();
    return row != null;
  }

  /// Menghapus tanda tarik supaya tarikan berikutnya mengambil semua data dari awal.
  Future<void> clearMarks(String householdId) async {
    for (final s in syncSpecs(db)) {
      await prefs.remove(_markKey(s, householdId));
    }
  }

  /// Dompet lokal yang belum tersambung ke rumah tangga dan belum dipakai sama sekali
  /// (mis. dompet dari onboarding setelah install ulang). Dibuang saat memulihkan akun
  /// supaya tidak muncul dompet ganda di samping dompet asli dari server.
  Future<void> discardUnusedLocalWallets() async {
    await db.customUpdate(
      'DELETE FROM wallets WHERE household_id IS NULL '
      'AND id NOT IN (SELECT wallet_id FROM tx_entries WHERE wallet_id IS NOT NULL) '
      'AND id NOT IN (SELECT to_wallet_id FROM tx_entries WHERE to_wallet_id IS NOT NULL) '
      'AND id NOT IN (SELECT wallet_id FROM bills WHERE wallet_id IS NOT NULL) '
      'AND id NOT IN (SELECT wallet_id FROM recurring_rules WHERE wallet_id IS NOT NULL) '
      'AND id NOT IN (SELECT wallet_id FROM goal_contributions WHERE wallet_id IS NOT NULL)',
      updates: {db.wallets},
      updateKind: UpdateKind.delete,
    );
  }

  /// Memberi `household_id` & `created_by` pada data yang dibuat sebelum bergabung/membuat rumah tangga.
  Future<void> adoptLocalData(String householdId, String userId) async {
    for (final s in syncSpecs(db)) {
      await db.customUpdate(
        'UPDATE ${s.local.actualTableName} SET household_id = ?, created_by = COALESCE(created_by, ?), dirty = 1 WHERE household_id IS NULL',
        variables: [Variable.withString(householdId), Variable.withString(userId)],
        updates: {s.local},
      );
    }
  }

  /// Saat bergabung ke rumah tangga yang sudah punya kategori bawaan,
  /// kategori bawaan lokal digabung ke milik rumah tangga (berdasarkan `seed_key`).
  Future<void> mergeSeedCategories(String householdId) async {
    final remote = await (db.select(db.categories)
          ..where((c) => c.householdId.equals(householdId) & c.seedKey.isNotNull() & c.dirty.equals(false)))
        .get();
    final byKey = {for (final c in remote) c.seedKey!: c.id};
    final local = await (db.select(db.categories)..where((c) => c.householdId.isNull() & c.seedKey.isNotNull())).get();
    await db.transaction(() async {
      for (final c in local) {
        final target = byKey[c.seedKey];
        if (target == null) continue;
        for (final t in ['tx_entries', 'budgets', 'recurring_rules', 'bills']) {
          await db.customUpdate('UPDATE $t SET category_id = ? WHERE category_id = ?', variables: [
            Variable.withString(target),
            Variable.withString(c.id),
          ]);
        }
        await (db.delete(db.categories)..where((x) => x.id.equals(c.id))).go();
      }
    });
  }
}
