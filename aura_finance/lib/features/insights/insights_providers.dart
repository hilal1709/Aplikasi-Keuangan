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

final budgetUsageProvider = Provider.family<List<BudgetUsage>, DateTime>((ref, month) {
  final m = DateId.monthStart(month);
  final budgets = ref.watch(budgetsProvider(m)).value ?? const [];
  final spend = ref.watch(spendByCategoryProvider((m, DateId.nextMonthStart(m)))).value ?? const [];
  final cats = ref.watch(categoryMapProvider);
  final byCat = {for (final s in spend) s.categoryId: s.amount};
  return [for (final b in budgets) BudgetUsage(b, cats[b.categoryId], byCat[b.categoryId] ?? 0)]
    ..sort((a, b) => b.ratio.compareTo(a.ratio));
});

/// Rata-rata pengeluaran 3 bulan penuh terakhir.
final avgMonthlyExpenseProvider = StreamProvider<int>((ref) {
  final db = ref.watch(dbProvider);
  final end = _thisMonth;
  final start = DateTime(end.year, end.month - 3);
  return db.watchTotals(start, end).map((t) => (t.expense / 3).round());
});

final healthProvider = Provider<HealthScore>((ref) {
  final totals = ref.watch(monthTotalsProvider(_thisMonth)).value ?? const PeriodTotals(income: 0, expense: 0);
  final usage = ref.watch(budgetUsageProvider(_thisMonth));
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
