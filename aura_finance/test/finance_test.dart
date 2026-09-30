import 'package:aura_finance/data/local/database.dart';
import 'package:aura_finance/domain/finance_math.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('id_ID'));

  group('computeHealth', () {
    test('skor penuh: tabungan 20%, budget aman, dana darurat 6 bulan', () {
      final h = computeHealth(
        thisMonth: const PeriodTotals(income: 10000000, expense: 8000000),
        netWorth: 48000000,
        avgMonthlyExpense: 8000000,
        budgetsTotal: 4,
        budgetsWithin: 4,
      );
      expect(h.score, 100);
      expect(h.label, 'Sangat sehat');
    });

    test('defisit & tanpa tabungan -> skor rendah', () {
      final h = computeHealth(
        thisMonth: const PeriodTotals(income: 5000000, expense: 7000000),
        netWorth: 0,
        avgMonthlyExpense: 7000000,
        budgetsTotal: 2,
        budgetsWithin: 0,
      );
      expect(h.score, 0);
      expect(h.savingsRate, lessThan(0));
    });

    test('belum ada budget memberi nilai tengah', () {
      final h = computeHealth(
        thisMonth: const PeriodTotals(income: 0, expense: 0),
        netWorth: 0,
        avgMonthlyExpense: 0,
        budgetsTotal: 0,
        budgetsWithin: 0,
      );
      expect(h.budgetAdherence, isNull);
      expect(h.score, 15);
    });
  });

  group('advance', () {
    test('bulanan dari tanggal 31 menyesuaikan akhir bulan', () {
      expect(advance(DateTime(2026, 1, 31, 8), Frequency.monthly), DateTime(2026, 2, 28, 8));
      expect(advance(DateTime(2026, 3, 31), Frequency.monthly), DateTime(2026, 4, 30));
    });
    test('tahunan & mingguan', () {
      expect(advance(DateTime(2028, 2, 29), Frequency.yearly), DateTime(2029, 2, 28));
      expect(advance(DateTime(2026, 9, 30), Frequency.weekly), DateTime(2026, 10, 7));
    });
  });

  group('bucketize', () {
    test('bulanan dikelompokkan per 7 hari', () {
      final days = [for (var d = 1; d <= 30; d++) DayFlow(DateTime(2026, 9, d), 1000, 500)];
      final b = bucketize(FlowPeriod.month, days);
      expect(b.length, 5);
      expect(b.first.income, 7000);
      expect(b.last.expense, 1000); // hari 29–30
    });
  });

  group('database', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('saldo dompet = saldo awal + masuk − keluar ± transfer, abaikan yang dihapus', () async {
      await db.upsertWallet(WalletsCompanion.insert(id: 'a', name: 'BCA', kind: WalletKind.bank, color: 0, initialBalance: const Value(1000000)));
      await db.upsertWallet(WalletsCompanion.insert(id: 'b', name: 'Tunai', kind: WalletKind.cash, color: 0));
      final now = DateTime.now();
      await db.upsertTx(TxEntriesCompanion.insert(id: 't1', kind: TxKind.income, amount: 500000, walletId: 'a', occurredAt: now));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't2', kind: TxKind.expense, amount: 200000, walletId: 'a', occurredAt: now));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't3', kind: TxKind.transfer, amount: 300000, walletId: 'a', toWalletId: const Value('b'), occurredAt: now));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't4', kind: TxKind.expense, amount: 999999, walletId: 'b', occurredAt: now));
      await db.softDeleteTx('t4');

      final balances = {for (final w in await db.watchWalletBalances().first) w.wallet.id: w.balance};
      expect(balances['a'], 1000000 + 500000 - 200000 - 300000);
      expect(balances['b'], 300000);

      final totals = await db.watchTotals(DateTime(now.year, now.month), DateTime(now.year, now.month + 1)).first;
      expect(totals.income, 500000);
      expect(totals.expense, 200000); // transfer bukan pengeluaran
    });

    test('hapus dompet beserta transaksinya menjaga saldo dompet lain', () async {
      await db.upsertWallet(WalletsCompanion.insert(id: 'a', name: 'BCA', kind: WalletKind.bank, color: 0, initialBalance: const Value(1000)));
      await db.upsertWallet(WalletsCompanion.insert(id: 'b', name: 'Tunai', kind: WalletKind.cash, color: 0));
      final now = DateTime.now();
      await db.upsertTx(TxEntriesCompanion.insert(id: 't1', kind: TxKind.transfer, amount: 300, walletId: 'a', toWalletId: const Value('b'), occurredAt: now));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't2', kind: TxKind.expense, amount: 50, walletId: 'a', occurredAt: now));
      expect(await db.countTxForWallet('b'), 1);

      await db.softDeleteWallet('b', withTransactions: true);
      final balances = {for (final w in await db.watchWalletBalances().first) w.wallet.id: w.balance};
      expect(balances.containsKey('b'), isFalse);
      expect(balances['a'], 1000 - 50); // transfer ke dompet terhapus ikut hilang
    });

    test('hapus kategori: transaksi tetap, budget ikut terhapus', () async {
      await db.upsertWallet(WalletsCompanion.insert(id: 'a', name: 'BCA', kind: WalletKind.bank, color: 0));
      final cat = (await db.watchCategories(kind: CategoryKind.expense).first).first;
      final month = DateTime(2026, 9);
      await db.upsertTx(TxEntriesCompanion.insert(id: 't1', kind: TxKind.expense, amount: 70, walletId: 'a', categoryId: Value(cat.id), occurredAt: DateTime(2026, 9, 5)));
      await db.upsertBudget(BudgetsCompanion.insert(id: 'b1', categoryId: cat.id, month: month, limitAmount: 100));

      await db.softDeleteCategory(cat.id);
      expect((await db.watchCategories().first).any((c) => c.id == cat.id), isFalse);
      expect(await db.watchBudgets(month).first, isEmpty);
      expect((await db.watchTx().first).single.categoryId, cat.id);
    });

    test('kategori bawaan terisi saat database dibuat', () async {
      final cats = await db.watchCategories().first;
      expect(cats.where((c) => c.kind == CategoryKind.expense), isNotEmpty);
      expect(cats.every((c) => c.seedKey != null), isTrue);
    });
  });
}
