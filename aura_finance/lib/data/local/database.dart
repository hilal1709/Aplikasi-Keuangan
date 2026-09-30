import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:uuid/uuid.dart';

import 'seed.dart';
import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

class WalletBalance {
  const WalletBalance(this.wallet, this.balance);
  final Wallet wallet;
  final int balance;
}

class PeriodTotals {
  const PeriodTotals({required this.income, required this.expense});
  final int income;
  final int expense;
  int get net => income - expense;
}

class DayFlow {
  const DayFlow(this.day, this.income, this.expense);
  final DateTime day;
  final int income;
  final int expense;
}

class CategorySpend {
  const CategorySpend(this.categoryId, this.amount);
  final String? categoryId;
  final int amount;
}

@DriftDatabase(
  tables: [Wallets, Categories, TxEntries, Budgets, Goals, GoalContributions, RecurringRules, Bills, Members],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'aura_finance'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await batch((b) => b.insertAll(categories, defaultCategories()));
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(members, members.avatar);
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = OFF');
        },
      );

  // ---------------------------------------------------------------------------
  // Dompet

  Stream<List<WalletBalance>> watchWalletBalances() {
    final query = customSelect(
      '''
      SELECT w.*,
        w.initial_balance
        + COALESCE((SELECT SUM(amount) FROM tx_entries t WHERE t.deleted_at IS NULL AND t.kind = 'income' AND t.wallet_id = w.id), 0)
        - COALESCE((SELECT SUM(amount) FROM tx_entries t WHERE t.deleted_at IS NULL AND t.kind IN ('expense','transfer') AND t.wallet_id = w.id), 0)
        + COALESCE((SELECT SUM(amount) FROM tx_entries t WHERE t.deleted_at IS NULL AND t.kind = 'transfer' AND t.to_wallet_id = w.id), 0)
        AS balance
      FROM wallets w
      WHERE w.deleted_at IS NULL AND w.archived = 0
      ORDER BY w.sort_order, w.created_at
      ''',
      readsFrom: {wallets, txEntries},
    );
    return query.watch().map(
          (rows) => rows.map((r) => WalletBalance(wallets.map(r.data), r.read<int>('balance'))).toList(),
        );
  }

  Future<void> upsertWallet(WalletsCompanion w) => into(wallets).insertOnConflictUpdate(_touchWallet(w));

  WalletsCompanion _touchWallet(WalletsCompanion w) => w.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true));

  Future<int> countTxForWallet(String walletId) async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM tx_entries WHERE deleted_at IS NULL AND (wallet_id = ? OR to_wallet_id = ?)',
      variables: [Variable.withString(walletId), Variable.withString(walletId)],
    ).getSingle();
    return r.read<int>('n');
  }

  /// Hapus dompet (soft delete). Jika [withTransactions], transaksi yang
  /// melibatkan dompet ini ikut dihapus supaya saldo dompet lain tetap benar.
  Future<void> softDeleteWallet(String id, {bool withTransactions = false}) => transaction(() async {
        final now = DateTime.now();
        if (withTransactions) {
          await customUpdate(
            'UPDATE tx_entries SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE deleted_at IS NULL AND (wallet_id = ? OR to_wallet_id = ?)',
            variables: [Variable.withDateTime(now), Variable.withDateTime(now), Variable.withString(id), Variable.withString(id)],
            updates: {txEntries},
          );
          await customUpdate(
            'UPDATE recurring_rules SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE deleted_at IS NULL AND wallet_id = ?',
            variables: [Variable.withDateTime(now), Variable.withDateTime(now), Variable.withString(id)],
            updates: {recurringRules},
          );
        }
        await _softDelete(wallets, id);
      });

  // ---------------------------------------------------------------------------
  // Kategori

  Stream<List<Category>> watchCategories({CategoryKind? kind}) {
    final q = select(categories)
      ..where((c) => c.deletedAt.isNull() & c.archived.equals(false))
      ..orderBy([(c) => OrderingTerm(expression: c.sortOrder), (c) => OrderingTerm(expression: c.name)]);
    if (kind != null) q.where((c) => c.kind.equalsValue(kind));
    return q.watch();
  }

  Future<int> countTxForCategory(String categoryId) async {
    final r = await customSelect(
      'SELECT COUNT(*) AS n FROM tx_entries WHERE deleted_at IS NULL AND category_id = ?',
      variables: [Variable.withString(categoryId)],
    ).getSingle();
    return r.read<int>('n');
  }

  /// Hapus kategori. Transaksinya tetap ada (tampil sebagai "Tanpa kategori"),
  /// budget untuk kategori ini ikut dihapus.
  Future<void> softDeleteCategory(String id) => transaction(() async {
        final now = DateTime.now();
        await customUpdate(
          'UPDATE budgets SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE deleted_at IS NULL AND category_id = ?',
          variables: [Variable.withDateTime(now), Variable.withDateTime(now), Variable.withString(id)],
          updates: {budgets},
        );
        await _softDelete(categories, id);
      });

  Future<void> upsertCategory(CategoriesCompanion c) =>
      into(categories).insertOnConflictUpdate(c.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  // ---------------------------------------------------------------------------
  // Transaksi

  Stream<List<TxEntry>> watchRecentTx({int limit = 5}) {
    return (select(txEntries)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
          ..limit(limit))
        .watch();
  }

  Stream<List<TxEntry>> watchTx({
    DateTime? from,
    DateTime? to,
    String? walletId,
    String? categoryId,
    String? createdBy,
    TxKind? kind,
    String search = '',
  }) {
    final q = select(txEntries)..where((t) => t.deletedAt.isNull());
    if (from != null) q.where((t) => t.occurredAt.isBiggerOrEqualValue(from));
    if (to != null) q.where((t) => t.occurredAt.isSmallerThanValue(to));
    if (walletId != null) q.where((t) => t.walletId.equals(walletId) | t.toWalletId.equals(walletId));
    if (categoryId != null) q.where((t) => t.categoryId.equals(categoryId));
    if (createdBy != null) q.where((t) => t.createdBy.equals(createdBy));
    if (kind != null) q.where((t) => t.kind.equalsValue(kind));
    if (search.trim().isNotEmpty) q.where((t) => t.note.like('%${search.trim()}%'));
    q.orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
    return q.watch();
  }

  /// Waktu terakhir transaksi ditulis dari perangkat ini (bukan dari sinkron).
  /// Dipakai agar peringatan budget hanya dipicu oleh catatan sendiri.
  DateTime? lastLocalTxWrite;

  Future<void> upsertTx(TxEntriesCompanion t) {
    lastLocalTxWrite = DateTime.now();
    return into(txEntries).insertOnConflictUpdate(t.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));
  }

  Future<void> softDeleteTx(String id) => _softDelete(txEntries, id);

  Future<void> restoreTx(String id) => (update(txEntries)..where((t) => t.id.equals(id))).write(
        TxEntriesCompanion(deletedAt: const Value(null), updatedAt: Value(DateTime.now()), dirty: const Value(true)),
      );

  Stream<PeriodTotals> watchTotals(DateTime from, DateTime to) {
    return customSelect(
      '''
      SELECT
        COALESCE(SUM(CASE WHEN kind = 'income' THEN amount END), 0) AS income,
        COALESCE(SUM(CASE WHEN kind = 'expense' THEN amount END), 0) AS expense
      FROM tx_entries
      WHERE deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?
      ''',
      variables: [Variable.withDateTime(from), Variable.withDateTime(to)],
      readsFrom: {txEntries},
    ).watchSingle().map((r) => PeriodTotals(income: r.read<int>('income'), expense: r.read<int>('expense')));
  }

  /// Arus kas per hari dalam rentang (hari tanpa transaksi diisi nol).
  Stream<List<DayFlow>> watchDailyFlow(DateTime from, DateTime to) {
    return (select(txEntries)
          ..where((t) =>
              t.deletedAt.isNull() &
              t.occurredAt.isBiggerOrEqualValue(from) &
              t.occurredAt.isSmallerThanValue(to) &
              t.kind.isNotValue(TxKind.transfer.name)))
        .watch()
        .map((rows) {
      final days = <DateTime, List<int>>{};
      for (var d = DateTime(from.year, from.month, from.day); d.isBefore(to); d = DateTime(d.year, d.month, d.day + 1)) {
        days[d] = [0, 0];
      }
      for (final t in rows) {
        final k = DateTime(t.occurredAt.year, t.occurredAt.month, t.occurredAt.day);
        final slot = days[k];
        if (slot == null) continue;
        if (t.kind == TxKind.income) {
          slot[0] += t.amount;
        } else {
          slot[1] += t.amount;
        }
      }
      return days.entries.map((e) => DayFlow(e.key, e.value[0], e.value[1])).toList();
    });
  }

  Stream<List<CategorySpend>> watchSpendByCategory(DateTime from, DateTime to, {TxKind kind = TxKind.expense}) {
    return customSelect(
      '''
      SELECT category_id, SUM(amount) AS total
      FROM tx_entries
      WHERE deleted_at IS NULL AND kind = ? AND occurred_at >= ? AND occurred_at < ?
      GROUP BY category_id
      ORDER BY total DESC
      ''',
      variables: [Variable.withString(kind.name), Variable.withDateTime(from), Variable.withDateTime(to)],
      readsFrom: {txEntries},
    ).watch().map((rows) => rows.map((r) => CategorySpend(r.readNullable<String>('category_id'), r.read<int>('total'))).toList());
  }

  // ---------------------------------------------------------------------------
  // Budget

  Stream<List<Budget>> watchBudgets(DateTime month) => (select(budgets)
        ..where((b) => b.deletedAt.isNull() & b.month.equals(month)))
      .watch();

  Future<void> upsertBudget(BudgetsCompanion b) =>
      into(budgets).insertOnConflictUpdate(b.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> softDeleteBudget(String id) => _softDelete(budgets, id);

  // ---------------------------------------------------------------------------
  // Target tabungan

  Stream<List<(Goal, int)>> watchGoalsWithSaved() {
    return customSelect(
      '''
      SELECT g.*, COALESCE((SELECT SUM(amount) FROM goal_contributions c WHERE c.goal_id = g.id AND c.deleted_at IS NULL), 0) AS saved
      FROM goals g
      WHERE g.deleted_at IS NULL AND g.archived = 0
      ORDER BY g.achieved_at IS NOT NULL, g.created_at
      ''',
      readsFrom: {goals, goalContributions},
    ).watch().map((rows) => rows.map((r) => (goals.map(r.data), r.read<int>('saved'))).toList());
  }

  Stream<List<GoalContribution>> watchContributions(String goalId) => (select(goalContributions)
        ..where((c) => c.goalId.equals(goalId) & c.deletedAt.isNull())
        ..orderBy([(c) => OrderingTerm.desc(c.occurredAt)]))
      .watch();

  Future<void> upsertGoal(GoalsCompanion g) =>
      into(goals).insertOnConflictUpdate(g.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> softDeleteGoal(String id) => _softDelete(goals, id);

  Future<void> addContribution(GoalContributionsCompanion c) =>
      into(goalContributions).insert(c.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  // ---------------------------------------------------------------------------
  // Berulang & tagihan

  Stream<List<RecurringRule>> watchRecurring() => (select(recurringRules)
        ..where((r) => r.deletedAt.isNull())
        ..orderBy([(r) => OrderingTerm(expression: r.nextRun)]))
      .watch();

  Future<void> upsertRecurring(RecurringRulesCompanion r) =>
      into(recurringRules).insertOnConflictUpdate(r.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> softDeleteRecurring(String id) => _softDelete(recurringRules, id);

  Stream<List<Bill>> watchBills() => (select(bills)
        ..where((b) => b.deletedAt.isNull())
        ..orderBy([(b) => OrderingTerm(expression: b.paidAt.isNotNull()), (b) => OrderingTerm(expression: b.dueDate)]))
      .watch();

  Future<void> upsertBill(BillsCompanion b) =>
      into(bills).insertOnConflictUpdate(b.copyWith(updatedAt: Value(DateTime.now()), dirty: const Value(true)));

  Future<void> softDeleteBill(String id) => _softDelete(bills, id);

  // ---------------------------------------------------------------------------

  Stream<List<Member>> watchMembers() => select(members).watch();

  Future<void> _softDelete<T extends Table, D>(TableInfo<T, D> table, String id) {
    final now = DateTime.now();
    return customUpdate(
      'UPDATE ${table.actualTableName} SET deleted_at = ?, updated_at = ?, dirty = 1 WHERE id = ?',
      variables: [Variable.withDateTime(now), Variable.withDateTime(now), Variable.withString(id)],
      updates: {table},
    );
  }
}
