import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:postgrest/postgrest.dart';

import '../remote/neon.dart';

import '../local/database.dart';

class SyncReport {
  const SyncReport(this.pushed, this.newTx);
  final int pushed;
  final List<TxEntry> newTx;
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

  /// Menjalankan satu putaran sinkron. Laporan berisi berapa baris terkirim
  /// dan transaksi baru milik perangkat ini (untuk notifikasi ke pasangan).
  Future<SyncReport> run(String householdId) async {
    client = await Neon.db();
    final specs = syncSpecs(db);
    var pushed = 0;
    final newTx = <TxEntry>[];
    for (final s in specs) {
      final rows = await _push(s, householdId);
      pushed += rows.length;
      if (identical(s.local, db.txEntries)) {
        newTx.addAll(rows.cast<TxEntry>().where((t) => t.deletedAt == null && t.updatedAt.difference(t.createdAt).inSeconds.abs() < 5));
      }
    }
    for (final s in specs) {
      await _pull(s, householdId);
    }
    await pullMembers(householdId);
    return SyncReport(pushed, newTx);
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

  Future<void> _pull(SyncSpec s, String householdId) async {
    final key = 'sync_mark_${s.remote}_$householdId';
    var mark = prefs.getString(key) ?? '1970-01-01T00:00:00Z';
    while (true) {
      final List<dynamic> rows = await client
          .from(s.remote)
          .select()
          .eq('household_id', householdId)
          .gt('server_updated_at', mark)
          .order('server_updated_at')
          .limit(1000);
      if (rows.isEmpty) break;

      await db.transaction(() async {
        for (final raw in rows.cast<Map<String, dynamic>>()) {
          final json = _fromRemote(s, raw);
          final local = await db.customSelect(
            'SELECT dirty, updated_at FROM ${s.local.actualTableName} WHERE id = ?',
            variables: [Variable.withString(json['id'] as String)],
          ).getSingleOrNull();
          if (local != null && local.read<bool>('dirty')) {
            final localUpdated = local.read<DateTime>('updated_at');
            final remoteUpdated = DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int);
            if (localUpdated.isAfter(remoteUpdated)) continue; // perubahan lokal menang
          }
          await db.into(s.local).insertOnConflictUpdate(s.fromJson(json));
        }
      });
      mark = (rows.last as Map<String, dynamic>)['server_updated_at'] as String;
      await prefs.setString(key, mark);
      if (rows.length < 1000) break;
    }
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
      final c = _camel(k);
      if (s.dateFields.contains(c) && v != null) {
        v = DateTime.parse(v as String).toLocal().millisecondsSinceEpoch;
      }
      out[c] = v;
    });
    return out;
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
