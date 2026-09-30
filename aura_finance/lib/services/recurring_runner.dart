import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:uuid/uuid.dart';

import '../data/local/database.dart';
import '../domain/finance_math.dart';

const _uuid = Uuid();

/// Mencatat transaksi berulang yang sudah jatuh tempo.
/// ID transaksi deterministik (UUID v5 dari aturan + tanggal) sehingga dua perangkat
/// yang menjalankan aturan yang sama tidak membuat duplikat setelah sinkronisasi.
Future<int> runDueRecurring(AppDatabase db, {DateTime? now}) async {
  final n = now ?? DateTime.now();
  final rules = await db.watchRecurring().first;
  var created = 0;
  for (final r in rules.where((r) => r.active)) {
    var next = r.nextRun;
    var guard = 0;
    while (!next.isAfter(n) && guard++ < 60) {
      // insertOrIgnore: jangan menimpa jika perangkat lain sudah membuat (dan mungkin mengeditnya).
      await db.into(db.txEntries).insert(mode: InsertMode.insertOrIgnore, TxEntriesCompanion.insert(
        id: _uuid.v5(Namespace.url.value, 'aura:${r.id}:${next.toUtc().toIso8601String()}'),
        kind: r.kind,
        amount: r.amount,
        walletId: r.walletId,
        categoryId: Value(r.categoryId),
        note: Value(r.note),
        occurredAt: next,
        recurringRuleId: Value(r.id),
        householdId: Value(r.householdId),
        createdBy: Value(r.createdBy),
      ));
      created++;
      next = advance(next, r.frequency);
    }
    if (next != r.nextRun) {
      await db.upsertRecurring(r.toCompanion(true).copyWith(nextRun: Value(next)));
    }
  }
  return created;
}
