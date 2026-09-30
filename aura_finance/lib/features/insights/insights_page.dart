import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/flow_chart.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';
import '../household/scope_switch.dart';
import 'export_service.dart';
import 'insights_providers.dart';

class InsightsPage extends ConsumerStatefulWidget {
  const InsightsPage({super.key});

  @override
  ConsumerState<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends ConsumerState<InsightsPage> {
  DateTime _month = DateId.monthStart(DateTime.now());
  int? _trendSel;
  bool _exporting = false;

  Future<void> _export(bool pdf) async {
    setState(() => _exporting = true);
    try {
      final s = ExportService(ref.read(dbProvider));
      pdf ? await s.sharePdf(_month) : await s.shareCsv(_month);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final top = MediaQuery.paddingOf(context).top;
    final isCurrent = _month == DateId.monthStart(DateTime.now());
    final totals = ref.watch(monthTotalsProvider(_month)).value ?? const PeriodTotals(income: 0, expense: 0);
    final spend = ref.watch(spendByCategoryProvider((_month, DateId.nextMonthStart(_month)))).value ?? const [];
    final cats = ref.watch(categoryMapProvider);
    final hidden = ref.watch(hideBalanceProvider);

    // Tren 6 bulan terakhir (hingga bulan terpilih).
    final trendFrom = DateTime(_month.year, _month.month - 5);
    final trendDays = ref.watch(dailyFlowProvider((trendFrom, DateId.nextMonthStart(_month)))).value ?? const <DayFlow>[];
    final trend = _monthly(trendFrom, trendDays);

    var i = 0;
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(AuraSpace.margin, top + AuraSpace.md, AuraSpace.margin, 140),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Insight', style: AuraType.headlineLg.copyWith(color: p.onSurface)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(DateId.month(_month), key: ValueKey(_month), style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
            NeuIconButton(HugeIcons.strokeRoundedArrowLeft01, label: 'Bulan sebelumnya', onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
            const SizedBox(width: 10),
            NeuIconButton(
              HugeIcons.strokeRoundedArrowRight01,
              label: 'Bulan berikutnya',
              onTap: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
            ),
          ],
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        const ScopeSwitch(showHint: false).staggerIn(i++),
        if (isCurrent) ...[const _HealthCard().staggerIn(i++), const SizedBox(height: AuraSpace.lg)],
        Row(
          children: [
            Expanded(child: _Summary(label: 'Pemasukan', value: totals.income, color: p.tertiary, hidden: hidden)),
            const SizedBox(width: AuraSpace.md),
            Expanded(child: _Summary(label: 'Pengeluaran', value: totals.expense, color: p.secondary, hidden: hidden)),
          ],
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.md),
        _Summary(
          label: totals.net >= 0 ? 'Tersisa bulan ini' : 'Defisit bulan ini',
          value: totals.net,
          color: totals.net >= 0 ? p.primary : p.error,
          hidden: hidden,
          wide: true,
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        NeuSurface(
          radius: AuraRadius.xl,
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader('Ke mana uangnya pergi'),
              const SizedBox(height: AuraSpace.md),
              if (spend.isEmpty)
                const ClayEmpty(kind: ClayKind.chart, size: 120, title: 'Belum ada pengeluaran', message: 'Grafik kategori muncul setelah ada pengeluaran bulan ini.')
              else
                _CategoryDonut(spend: spend, cats: cats, total: totals.expense, hidden: hidden),
            ],
          ),
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        NeuSurface(
          radius: AuraRadius.xl,
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SectionHeader('Tren 6 bulan'),
              const SizedBox(height: AuraSpace.md),
              Builder(builder: (context) {
                final sel = (_trendSel ?? trend.length - 1).clamp(0, trend.length - 1);
                final b = trend[sel];
                return Column(
                  children: [
                    Row(
                      children: [
                        Text(b.caption, style: AuraType.labelMd.copyWith(color: p.onSurface)),
                        const Spacer(),
                        Text(hidden ? '+•••' : Rupiah.compact(b.income, signed: true), style: AuraType.labelSm.copyWith(color: p.tertiary, fontSize: 11)),
                        const SizedBox(width: 10),
                        Text(hidden ? '-•••' : Rupiah.compact(-b.expense), style: AuraType.labelSm.copyWith(color: p.secondary, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.sm),
                    FlowChart(buckets: trend, selected: sel, onSelect: (v) => setState(() => _trendSel = v)),
                  ],
                );
              }),
            ],
          ),
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        Row(
          children: [
            Expanded(
              child: _LinkTile(icon: HugeIcons.strokeRoundedTarget02, label: 'Budget', onTap: () => context.push('/budgets')),
            ),
            const SizedBox(width: AuraSpace.md),
            Expanded(
              child: _LinkTile(icon: HugeIcons.strokeRoundedRepeat, label: 'Berulang', onTap: () => context.push('/recurring')),
            ),
          ],
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        Row(
          children: [
            Expanded(
              child: ShadButton.outline(
                enabled: !_exporting,
                onPressed: () => _export(false),
                leading: const AuraIcon(HugeIcons.strokeRoundedFileExport, size: 18),
                child: const Text('Ekspor CSV'),
              ),
            ),
            const SizedBox(width: AuraSpace.md),
            Expanded(
              child: ShadButton.outline(
                enabled: !_exporting,
                onPressed: () => _export(true),
                leading: const AuraIcon(HugeIcons.strokeRoundedShare08, size: 18),
                child: const Text('Laporan PDF'),
              ),
            ),
          ],
        ).staggerIn(i++),
      ],
    );
  }

  List<FlowBucket> _monthly(DateTime from, List<DayFlow> days) {
    final buckets = <FlowBucket>[];
    for (var m = 0; m < 6; m++) {
      final month = DateTime(from.year, from.month + m);
      final inMonth = days.where((d) => d.day.year == month.year && d.day.month == month.month);
      buckets.add(FlowBucket(
        label: DateFormat('MMM', 'id_ID').format(month).substring(0, 3),
        caption: DateId.month(month),
        income: inMonth.fold(0, (s, d) => s + d.income),
        expense: inMonth.fold(0, (s, d) => s + d.expense),
      ));
    }
    return buckets;
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.label, required this.value, required this.color, required this.hidden, this.wide = false});
  final String label;
  final int value;
  final Color color;
  final bool hidden;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuSurface(
      depth: -1,
      radius: AuraRadius.lg,
      color: p.surfaceContainer,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: wide
          ? Row(
              children: [
                Text(label, style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                const Spacer(),
                MoneyText(value, hidden: hidden, style: AuraType.headlineSm.copyWith(color: color)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                const SizedBox(height: 4),
                MoneyText(value, hidden: hidden, style: AuraType.headlineSm.copyWith(color: color)),
              ],
            ),
    );
  }
}

class _LinkTile extends StatelessWidget {
  const _LinkTile({required this.icon, required this.label, required this.onTap});
  final List<List<dynamic>> icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuPressable(
      onTap: onTap,
      radius: AuraRadius.lg,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        children: [
          AuraIcon(icon, color: p.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(label, style: AuraType.labelLg.copyWith(color: p.onSurface))),
          AuraIcon(HugeIcons.strokeRoundedArrowRight01, size: 18, color: p.outline),
        ],
      ),
    );
  }
}

class _HealthCard extends ConsumerWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final h = ref.watch(healthProvider);
    String pct(double v) => '${(v * 100).round()}%';
    return NeuSurface(
      radius: AuraRadius.xl,
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Column(
        children: [
          SizedBox(height: 150, child: _Gauge(score: h.score)),
          Text(h.label, style: AuraType.headlineSm.copyWith(color: p.onSurface)),
          Text('Skor kesehatan finansial bulan ini', style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: AuraSpace.md),
          _Factor(
            label: 'Rasio tabungan',
            detail: h.savingsRate < 0 ? 'Pengeluaran melebihi pemasukan' : '${pct(h.savingsRate.clamp(0, 1))} dari pemasukan (ideal ≥ 20%)',
            value: (h.savingsRate.clamp(0.0, 0.2)) / 0.2,
          ),
          _Factor(
            label: 'Kepatuhan budget',
            detail: h.budgetAdherence == null ? 'Belum ada budget bulan ini' : '${pct(h.budgetAdherence!)} kategori masih aman',
            value: h.budgetAdherence ?? 0.5,
          ),
          _Factor(
            label: 'Dana darurat',
            detail: '${h.monthsCovered.toStringAsFixed(1)} bulan pengeluaran (ideal ≥ 6)',
            value: h.monthsCovered.clamp(0, 6) / 6,
          ),
        ],
      ),
    );
  }
}

class _Factor extends StatelessWidget {
  const _Factor({required this.label, required this.detail, required this.value});
  final String label;
  final String detail;
  final double value;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AuraType.labelMd.copyWith(color: p.onSurface)),
          Text(detail, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 6),
          NeuProgress(value: value, height: 10, colors: [p.tertiary, p.tertiaryContainer]),
        ],
      ),
    );
  }
}

/// Gauge setengah lingkaran dengan jarum yang berayun ke posisi skor.
class _Gauge extends StatelessWidget {
  const _Gauge({required this.score});
  final int score;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: score / 100),
      duration: const Duration(milliseconds: 1600),
      curve: Curves.elasticOut,
      builder: (context, v, _) => CustomPaint(
        painter: _GaugePainter(v, p),
        child: Align(
          alignment: const Alignment(0, 0.75),
          child: Text('${(v * 100).round().clamp(0, 100)}', style: AuraType.displayLg.copyWith(color: p.onSurface)),
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter(this.v, this.p);
  final double v;
  final AuraPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height - 10);
    final r = math.min(size.width / 2, size.height) - 16;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      math.pi,
      math.pi,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..color = p.surfaceHigh,
    );
    canvas.drawArc(
      rect,
      math.pi,
      math.pi * v.clamp(0, 1),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: math.pi,
          endAngle: math.pi * 2,
          colors: [p.primaryContainer, const Color(0xFFE7A977), p.tertiaryContainer, p.tertiary],
        ).createShader(rect),
    );
    // Ujung busur: titik putih.
    final a = math.pi + math.pi * v.clamp(0, 1);
    canvas.drawCircle(Offset(c.dx + r * math.cos(a), c.dy + r * math.sin(a)), 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter o) => o.v != v || o.p != p;
}

class _CategoryDonut extends StatefulWidget {
  const _CategoryDonut({required this.spend, required this.cats, required this.total, required this.hidden});
  final List<CategorySpend> spend;
  final Map<String, Category> cats;
  final int total;
  final bool hidden;

  @override
  State<_CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<_CategoryDonut> {
  int? _sel;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final items = widget.spend.take(6).toList();
    final rest = widget.spend.skip(6).fold<int>(0, (s, c) => s + c.amount);
    final slices = [
      for (final s in items)
        (
          name: widget.cats[s.categoryId]?.name ?? 'Tanpa kategori',
          amount: s.amount,
          color: Color(widget.cats[s.categoryId]?.color ?? p.outline.toARGB32()),
          icon: widget.cats[s.categoryId]?.icon ?? 'other',
        ),
      if (rest > 0) (name: 'Lainnya', amount: rest, color: p.outlineVariant, icon: 'other'),
    ];
    final total = math.max(1, widget.total);
    final sel = _sel;

    return Column(
      children: [
        SizedBox(
          height: 200,
          child: LayoutBuilder(builder: (context, box) {
            return GestureDetector(
              onTapDown: (d) {
                final c = Offset(box.maxWidth / 2, 100);
                final v = d.localPosition - c;
                if (v.distance < 50 || v.distance > 100) return setState(() => _sel = null);
                var ang = math.atan2(v.dy, v.dx) + math.pi / 2;
                if (ang < 0) ang += math.pi * 2;
                var acc = 0.0;
                for (var i = 0; i < slices.length; i++) {
                  acc += slices[i].amount / total * math.pi * 2;
                  if (ang <= acc) {
                    HapticFeedback.selectionClick();
                    setState(() => _sel = _sel == i ? null : i);
                    return;
                  }
                }
              },
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 1100),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => CustomPaint(
                  size: Size(box.maxWidth, 200),
                  painter: _DonutPainter(slices.map((s) => (s.amount / total, s.color)).toList(), t, sel, p),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: Column(
                        key: ValueKey(sel),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(sel == null ? 'Total' : slices[sel].name, style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant)),
                          Text(
                            widget.hidden ? 'Rp •••' : Rupiah.compact(sel == null ? widget.total : slices[sel].amount),
                            style: AuraType.headlineSm.copyWith(color: p.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: AuraSpace.md),
        for (final (i, s) in slices.indexed)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _sel = _sel == i ? null : i),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: sel == null || sel == i ? 1 : 0.45,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CategoryBadge(icon: s.icon, color: s.color.toARGB32(), size: 34),
                    const SizedBox(width: 10),
                    Expanded(child: Text(s.name, style: AuraType.labelLg.copyWith(color: p.onSurface))),
                    Text('${(s.amount / total * 100).round()}%', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 84,
                      child: Text(
                        widget.hidden ? 'Rp •••' : Rupiah.compact(s.amount),
                        textAlign: TextAlign.right,
                        style: AuraType.labelLg.copyWith(color: p.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.slices, this.t, this.sel, this.p);
  final List<(double, Color)> slices;
  final double t;
  final int? sel;
  final AuraPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, 100);
    const r = 75.0;
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 28
      ..color = p.surfaceHigh);
    var start = -math.pi / 2;
    const gap = 0.035;
    for (var i = 0; i < slices.length; i++) {
      final sweep = slices[i].$1 * math.pi * 2 * t;
      final active = sel == i;
      final mid = start + sweep / 2;
      final offset = active ? Offset(math.cos(mid) * 6, math.sin(mid) * 6) : Offset.zero;
      canvas.drawArc(
        Rect.fromCircle(center: c + offset, radius: r),
        start + gap / 2,
        math.max(0.001, sweep - gap),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = active ? 34 : 28
          ..strokeCap = StrokeCap.butt
          ..color = sel == null || active ? slices[i].$2 : slices[i].$2.withValues(alpha: 0.35),
      );
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter o) => o.t != t || o.sel != sel || o.slices != slices;
}
