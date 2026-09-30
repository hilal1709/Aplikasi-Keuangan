import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/date_id.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';
import '../../domain/finance_math.dart';

DateTime get _thisMonth => DateId.monthStart(DateTime.now());

/// Budget bulan ini beserta realisasinya.
class BudgetUsage {
  const BudgetUsage(this.budget, this.category, this.spent);
  final Budget budget;
  final Category? category;
  final int spent;
  double get ratio => budget.limitAmount <= 0 ? 0 : spent / budget.limitAmount;
  bool get over => spent > budget.limitAmount;
}

/// Semua budget bulan itu. Budget bersama menghitung pengeluaran dari dompet bersama
/// (angkanya sama di HP semua anggota); budget pribadi dari dompet pribadiku.
/// Tanpa rumah tangga semua dompet dihitung.
final budgetUsageProvider = Provider.family<List<BudgetUsage>, DateTime>((ref, month) {
  final m = DateId.monthStart(month);
  final end = DateId.nextMonthStart(m);
  final inHousehold = ref.watch(householdIdProvider) != null;
  final budgets = ref.watch(budgetsProvider(m)).value ?? const [];
  Map<String?, int> spendOf(ViewScope s) =>
      {for (final x in ref.watch(spendForScopeProvider((m, end, s))).value ?? const <CategorySpend>[]) x.categoryId: x.amount};
  final all = inHousehold ? const <String?, int>{} : spendOf(ViewScope.all);
  final shared = inHousehold ? spendOf(ViewScope.shared) : const <String?, int>{};
  final mine = inHousehold ? spendOf(ViewScope.mine) : const <String?, int>{};
  final cats = ref.watch(categoryMapProvider);
  int spentFor(Budget b) => ((!inHousehold ? all : (b.isShared ? shared : mine))[b.categoryId]) ?? 0;
  return [for (final b in budgets) BudgetUsage(b, cats[b.categoryId], spentFor(b))]..sort((a, b) => b.ratio.compareTo(a.ratio));
});

/// Budget yang tampil di Beranda/Insight sesuai cakupan tampilan.
final scopedBudgetUsageProvider = Provider.family<List<BudgetUsage>, DateTime>((ref, month) {
  final list = ref.watch(budgetUsageProvider(month));
  return switch (ref.watch(viewScopeProvider)) {
    ViewScope.all => list,
    ViewScope.shared => list.where((u) => u.budget.isShared).toList(),
    ViewScope.mine => list.where((u) => !u.budget.isShared).toList(),
  };
});

/// Rata-rata pengeluaran 3 bulan penuh terakhir.
final avgMonthlyExpenseProvider = StreamProvider<int>((ref) {
  final db = ref.watch(dbProvider);
  final end = _thisMonth;
  final start = DateTime(end.year, end.month - 3);
  return db.watchTotals(start, end, walletIds: ref.watch(scopedWalletIdsProvider)).map((t) => (t.expense / 3).round());
});

final healthProvider = Provider<HealthScore>((ref) {
  final totals = ref.watch(monthTotalsProvider(_thisMonth)).value ?? const PeriodTotals(income: 0, expense: 0);
  final usage = ref.watch(scopedBudgetUsageProvider(_thisMonth));
  final avg = ref.watch(avgMonthlyExpenseProvider).value ?? 0;
  return computeHealth(
    thisMonth: totals,
    netWorth: ref.watch(netWorthProvider),
    // Pengguna baru belum punya riwayat 3 bulan; pakai pengeluaran bulan ini sebagai perkiraan.
    avgMonthlyExpense: avg > 0 ? avg : totals.expense,
    budgetsTotal: usage.length,
    budgetsWithin: usage.where((u) => !u.over).length,
  );
});

final flowPeriodProvider = NotifierProvider<FlowPeriodNotifier, FlowPeriod>(FlowPeriodNotifier.new);

class FlowPeriodNotifier extends Notifier<FlowPeriod> {
  @override
  FlowPeriod build() => FlowPeriod.week;
  void set(FlowPeriod p) => state = p;
}
