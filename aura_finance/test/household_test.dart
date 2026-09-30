import 'package:aura_finance/data/local/database.dart';
import 'package:aura_finance/data/sync/sync_engine.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> wallet(String id, {bool shared = true, int initial = 0, String? by}) => db.upsertWallet(WalletsCompanion.insert(
        id: id,
        name: id,
        kind: WalletKind.bank,
        color: 0,
        initialBalance: Value(initial),
        isShared: Value(shared),
        createdBy: Value(by),
      ));

  group('setor target dari dompet', () {
    test('setoran mengurangi saldo dompet, penarikan menambah kembali', () async {
      await wallet('bca', initial: 1000000);
      await db.upsertGoal(GoalsCompanion.insert(id: 'g', name: 'Liburan', target: 500000, illustration: 'travel', color: 0));
      await db.addContribution(GoalContributionsCompanion.insert(id: 'c1', goalId: 'g', amount: 300000, occurredAt: DateTime.now(), walletId: const Value('bca')));
      await db.addContribution(GoalContributionsCompanion.insert(id: 'c2', goalId: 'g', amount: -50000, occurredAt: DateTime.now(), walletId: const Value('bca')));
      // Setoran tanpa dompet hanya dicatat di target.
      await db.addContribution(GoalContributionsCompanion.insert(id: 'c3', goalId: 'g', amount: 100000, occurredAt: DateTime.now()));

      final balance = (await db.watchWalletBalances().first).single.balance;
      expect(balance, 1000000 - 300000 + 50000);
      final saved = (await db.watchGoalsWithSaved().first).single.$2;
      expect(saved, 300000 - 50000 + 100000);
    });

    test('menghapus target mengembalikan uang ke dompet', () async {
      await wallet('bca', initial: 1000000);
      await db.upsertGoal(GoalsCompanion.insert(id: 'g', name: 'Gadget', target: 500000, illustration: 'gadget', color: 0));
      await db.addContribution(GoalContributionsCompanion.insert(id: 'c1', goalId: 'g', amount: 400000, occurredAt: DateTime.now(), walletId: const Value('bca')));
      expect((await db.watchWalletBalances().first).single.balance, 600000);

      await db.softDeleteGoal('g');
      expect((await db.watchWalletBalances().first).single.balance, 1000000);
      expect(await db.watchGoalsWithSaved().first, isEmpty);
    });
  });

  group('cakupan Semua / Bersama / Pribadi', () {
    test('total & pengeluaran per kategori hanya menghitung dompet yang dipilih', () async {
      await wallet('bersama');
      await wallet('pribadi', shared: false);
      final d = DateTime(2026, 9, 10);
      await db.upsertTx(TxEntriesCompanion.insert(id: 't1', kind: TxKind.expense, amount: 70000, walletId: 'bersama', categoryId: const Value('makan'), occurredAt: d));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't2', kind: TxKind.expense, amount: 30000, walletId: 'pribadi', categoryId: const Value('makan'), occurredAt: d));
      await db.upsertTx(TxEntriesCompanion.insert(id: 't3', kind: TxKind.income, amount: 500000, walletId: 'pribadi', occurredAt: d));
      // Transaksi di dompet yang tidak terlihat (mis. dompet pribadi pasangan) tidak ikut.
      await db.upsertTx(TxEntriesCompanion.insert(id: 't4', kind: TxKind.expense, amount: 999, walletId: 'tak-dikenal', occurredAt: d));

      final from = DateTime(2026, 9), to = DateTime(2026, 10);
      final all = await db.watchTotals(from, to, walletIds: {'bersama', 'pribadi'}).first;
      expect((all.income, all.expense), (500000, 100000));
      final shared = await db.watchTotals(from, to, walletIds: {'bersama'}).first;
      expect((shared.income, shared.expense), (0, 70000));
      final mine = await db.watchSpendByCategory(from, to, walletIds: {'pribadi'}).first;
      expect(mine.single.amount, 30000);
      expect(await db.watchTotals(from, to, walletIds: {}).first.then((t) => t.expense), 0);
    });
  });

  group('perubahan dari Pusher', () {
    late SyncEngine engine;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      engine = SyncEngine(db, await SharedPreferences.getInstance());
    });

    Map<String, dynamic> goalRow(String id, {String hid = 'h1', required DateTime updated, String name = 'Bukit'}) => {
          'id': id,
          'household_id': hid,
          'created_by': 'fanny',
          'created_at': updated.toUtc().toIso8601String(),
          'updated_at': updated.toUtc().toIso8601String(),
          'deleted_at': null,
          'name': name,
          'target': 500000,
          'deadline': null,
          'illustration': 'travel',
          'color': 0,
          'achieved_at': null,
          'archived': false,
          'is_shared': true,
        };

    test('baris dari pasangan langsung muncul; rumah tangga lain diabaikan', () async {
      final now = DateTime.now();
      final n = await engine.applyChanges({
        'goals': [goalRow('g1', updated: now), goalRow('g2', hid: 'h-lain', updated: now)],
      }, 'h1');
      expect(n, 1);
      final goals = await db.watchGoalsWithSaved().first;
      expect(goals.single.$1.name, 'Bukit');
      expect(goals.single.$1.dirty, isFalse);
    });

    test('perubahan lokal yang belum terkirim & lebih baru tidak tertimpa', () async {
      final old = DateTime.now().subtract(const Duration(minutes: 5));
      await db.upsertGoal(GoalsCompanion.insert(id: 'g1', name: 'Versi lokal', target: 1, illustration: 'jar', color: 0, householdId: const Value('h1')));
      await engine.applyChanges({
        'goals': [goalRow('g1', updated: old, name: 'Versi lama')],
      }, 'h1');
      expect((await db.watchGoalsWithSaved().first).single.$1.name, 'Versi lokal');
    });
  });
}
