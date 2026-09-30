import 'dart:math' as math;

import 'package:intl/intl.dart';

import '../core/utils/date_id.dart';
import '../core/widgets/flow_chart.dart';
import '../data/local/database.dart';

enum FlowPeriod { week, month, year }

/// Rentang tanggal [from, to) untuk periode grafik, berakhir di [now].
(DateTime, DateTime) flowRange(FlowPeriod period, DateTime now) {
  final today = DateId.dateOnly(now);
  return switch (period) {
    FlowPeriod.week => (today.subtract(const Duration(days: 6)), today.add(const Duration(days: 1))),
    FlowPeriod.month => (DateId.monthStart(now), DateId.nextMonthStart(now)),
    FlowPeriod.year => (DateTime(now.year), DateTime(now.year + 1)),
  };
}

/// Mengelompokkan arus kas harian menjadi batang grafik.
List<FlowBucket> bucketize(FlowPeriod period, List<DayFlow> days) {
  switch (period) {
    case FlowPeriod.week:
      return [
        for (final d in days)
          FlowBucket(label: DateId.weekdayShort(d.day), caption: DateId.dayLong(d.day), income: d.income, expense: d.expense),
      ];
    case FlowPeriod.month:
      final buckets = <FlowBucket>[];
      for (var start = 0; start < days.length; start += 7) {
        final chunk = days.sublist(start, math.min(start + 7, days.length));
        buckets.add(FlowBucket(
          label: 'M${buckets.length + 1}',
          caption: '${chunk.first.day.day}–${chunk.last.day.day} ${DateFormat('MMM', 'id_ID').format(chunk.first.day)}',
          income: chunk.fold(0, (s, d) => s + d.income),
          expense: chunk.fold(0, (s, d) => s + d.expense),
        ));
      }
      return buckets;
    case FlowPeriod.year:
      final byMonth = List.generate(12, (_) => [0, 0]);
      for (final d in days) {
        byMonth[d.day.month - 1][0] += d.income;
        byMonth[d.day.month - 1][1] += d.expense;
      }
      final year = days.isEmpty ? DateTime.now().year : days.first.day.year;
      return [
        for (var m = 0; m < 12; m++)
          FlowBucket(
            label: DateFormat('MMM', 'id_ID').format(DateTime(year, m + 1)).substring(0, 3),
            caption: DateId.month(DateTime(year, m + 1)),
            income: byMonth[m][0],
            expense: byMonth[m][1],
          ),
      ];
  }
}

/// Indeks batang "sekarang" untuk dipilih sebagai default.
int currentBucketIndex(FlowPeriod period, DateTime now, int length) => switch (period) {
      FlowPeriod.week => length - 1,
      FlowPeriod.month => ((now.day - 1) ~/ 7).clamp(0, length - 1),
      FlowPeriod.year => now.month - 1,
    };

class HealthScore {
  const HealthScore({required this.score, required this.savingsRate, required this.budgetAdherence, required this.monthsCovered});
  final int score;
  final double savingsRate;

  /// null jika belum ada budget.
  final double? budgetAdherence;
  final double monthsCovered;

  String get label {
    if (score >= 80) return 'Sangat sehat';
    if (score >= 60) return 'Sehat';
    if (score >= 40) return 'Cukup';
    return 'Perlu perhatian';
  }
}

/// Skor 0–100 dari tiga komponen:
/// - rasio tabungan bulan ini (40 poin, penuh di >= 20%),
/// - kepatuhan budget (30 poin; 15 jika belum ada budget),
/// - dana darurat: kekayaan bersih / rata-rata pengeluaran bulanan (30 poin, penuh di >= 6 bulan).
HealthScore computeHealth({
  required PeriodTotals thisMonth,
  required int netWorth,
  required int avgMonthlyExpense,
  required int budgetsTotal,
  required int budgetsWithin,
}) {
  final savingsRate = thisMonth.income <= 0 ? (thisMonth.expense == 0 ? 0.0 : -1.0) : thisMonth.net / thisMonth.income;
  final savingsPts = (savingsRate.clamp(0.0, 0.2) / 0.2) * 40;

  final adherence = budgetsTotal == 0 ? null : budgetsWithin / budgetsTotal;
  final budgetPts = adherence == null ? 15.0 : adherence * 30;

  final months = avgMonthlyExpense <= 0 ? (netWorth > 0 ? 6.0 : 0.0) : netWorth / avgMonthlyExpense;
  final emergencyPts = (months.clamp(0.0, 6.0) / 6) * 30;

  return HealthScore(
    score: (savingsPts + budgetPts + emergencyPts).round().clamp(0, 100),
    savingsRate: savingsRate,
    budgetAdherence: adherence,
    monthsCovered: math.max(0, months),
  );
}

/// Menggeser tanggal sesuai frekuensi (tanggal 31 aman untuk bulan pendek).
DateTime advance(DateTime d, Frequency f) {
  switch (f) {
    case Frequency.daily:
      return d.add(const Duration(days: 1));
    case Frequency.weekly:
      return d.add(const Duration(days: 7));
    case Frequency.monthly:
      return _addMonths(d, 1);
    case Frequency.yearly:
      return _addMonths(d, 12);
  }
}

DateTime _addMonths(DateTime d, int months) {
  final target = DateTime(d.year, d.month + months);
  final lastDay = DateTime(target.year, target.month + 1, 0).day;
  return DateTime(target.year, target.month, math.min(d.day, lastDay), d.hour, d.minute);
}

/// Estimasi tanggal target tercapai dari rata-rata setoran per bulan.
DateTime? estimateGoalDate({required int target, required int saved, required List<GoalContribution> history, DateTime? now}) {
  if (saved >= target) return null;
  if (history.isEmpty) return null;
  final n = now ?? DateTime.now();
  final first = history.map((c) => c.occurredAt).reduce((a, b) => a.isBefore(b) ? a : b);
  final monthsSpan = math.max(1.0, n.difference(first).inDays / 30.0);
  final perMonth = saved / monthsSpan;
  if (perMonth <= 0) return null;
  final monthsLeft = (target - saved) / perMonth;
  return n.add(Duration(days: (monthsLeft * 30).ceil()));
}
