import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/icons/category_icons.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/flow_chart.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/feedback.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';
import '../../data/sync/sync_providers.dart';
import '../../domain/finance_math.dart';
import '../goals/goal_card.dart';
import '../insights/insights_providers.dart';
import '../transactions/add_tx_sheet.dart';
import '../transactions/tx_tile.dart';

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = MediaQuery.paddingOf(context).top;
    final recent = ref.watch(recentTxProvider).value;
    final goals = ref.watch(goalsProvider).value ?? const [];

    var i = 0;
    return RefreshIndicator.adaptive(
      onRefresh: () => ref.read(syncControllerProvider.notifier).syncNow(),
      edgeOffset: top,
      child: ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: EdgeInsets.fromLTRB(AuraSpace.margin, top + AuraSpace.md, AuraSpace.margin, 140),
        children: [
          const _Greeting().staggerIn(i++),
          const SizedBox(height: AuraSpace.md),
          const _Banners(),
          const SizedBox(height: AuraSpace.lg),
          const _HeroCard().staggerIn(i++),
          const SizedBox(height: AuraSpace.lg),
          const _QuickActions().staggerIn(i++),
          const SizedBox(height: AuraSpace.lg),
          const _CashflowCard().staggerIn(i++),
          const _UpcomingBills(),
          const SizedBox(height: AuraSpace.lg),
          SectionHeader(
            'Target Tabungan',
            trailing: PillLink(goals.isEmpty ? 'Buat target' : 'Semua', onTap: () => context.go('/goals')),
          ).staggerIn(i++),
          const SizedBox(height: AuraSpace.sm + 4),
          if (goals.isEmpty)
            NeuSurface(
              padding: const EdgeInsets.all(AuraSpace.md),
              child: Row(
                children: [
                  const ClayArt(ClayKind.travel, size: 84),
                  const SizedBox(width: AuraSpace.md),
                  Expanded(
                    child: Text(
                      'Liburan, dana darurat, atau gadget baru — beri nama impianmu dan pantau progresnya di sini.',
                      style: AuraType.bodyMd.copyWith(color: context.aura.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ).staggerIn(i++)
          else
            for (final (g, saved) in goals.take(2))
              Padding(padding: const EdgeInsets.only(bottom: AuraSpace.md), child: GoalCard(goal: g, saved: saved).staggerIn(i++)),
          const SizedBox(height: AuraSpace.md),
          SectionHeader('Transaksi Terkini', trailing: PillLink('Lihat semua', onTap: () => context.push('/history'))).staggerIn(i++),
          const SizedBox(height: AuraSpace.sm + 4),
          if (recent != null && recent.isEmpty)
            const ClayEmpty(
              kind: ClayKind.jar,
              title: 'Belum ada catatan',
              message: 'Tekan tombol + di bawah untuk mencatat pemasukan atau pengeluaran pertamamu.',
            )
          else
            for (final tx in recent ?? const <TxEntry>[])
              Padding(padding: const EdgeInsets.only(bottom: 12), child: TxTile(tx).staggerIn(i++)),
        ],
      ),
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final name = ref.watch(displayNameProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final health = ref.watch(healthProvider);
    final sync = ref.watch(syncControllerProvider);
    final month = ref.watch(monthTotalsProvider(DateId.monthStart(DateTime.now()))).value;
    final noData = month == null || (month.income == 0 && month.expense == 0);
    final dot = noData
        ? p.outline
        : health.score >= 60
            ? p.tertiaryContainer
            : (health.score >= 40 ? const Color(0xFFE7A977) : p.primaryContainer);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? DateId.greeting() : '${DateId.greeting()}, ${name.split(' ').first}',
                style: AuraType.headlineMd.copyWith(color: p.onSurface),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  NeuSurface(
                    depth: 0.7,
                    radius: AuraRadius.pill,
                    color: p.surfaceContainer,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        RepaintBoundary(child: _Breathing(color: dot)),
                        const SizedBox(width: 6),
                        Text(
                          noData ? 'SKOR MUNCUL SETELAH MENCATAT' : '${health.label.toUpperCase()} · SKOR ${health.score}',
                          style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (sync.enabled) _SyncBadge(state: sync),
                ],
              ),
            ],
          ),
        ),
        NeuPressable(
          onTap: () => ref.read(hideBalanceProvider.notifier).toggle(),
          circle: true,
          width: 48,
          height: 48,
          semanticLabel: hidden ? 'Tampilkan saldo' : 'Sembunyikan saldo',
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (c, a) => RotationTransition(
                turns: Tween(begin: 0.75, end: 1.0).animate(a),
                child: FadeTransition(opacity: a, child: c),
              ),
              child: AuraIcon(
                hidden ? HugeIcons.strokeRoundedViewOff : HugeIcons.strokeRoundedView,
                key: ValueKey(hidden),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Titik status yang "bernapas" pelan.
class _Breathing extends StatefulWidget {
  const _Breathing({required this.color});
  final Color color;

  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color,
          shape: BoxShape.circle,
          boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.7), blurRadius: 4 + 6 * _c.value, spreadRadius: _c.value)],
        ),
      ),
    );
  }
}

class _SyncBadge extends StatelessWidget {
  const _SyncBadge({required this.state});
  final SyncState state;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final (label, color) = switch (state.status) {
      SyncStatus.syncing => ('Menyinkron', p.primary),
      SyncStatus.offline => ('Offline', p.outline),
      SyncStatus.error => ('Gagal sinkron', p.error),
      SyncStatus.idle => (state.pending > 0 ? '${state.pending} menunggu' : 'Tersinkron', p.tertiary),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: Text(label, key: ValueKey(label), style: AuraType.labelSm.copyWith(color: color)),
    );
  }
}

class _HeroCard extends ConsumerWidget {
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final hidden = ref.watch(hideBalanceProvider);
    final netWorth = ref.watch(netWorthProvider);
    final wallets = ref.watch(walletBalancesProvider).value ?? const [];
    final now = DateTime.now();
    final month = ref.watch(monthTotalsProvider(DateId.monthStart(now))).value ?? const PeriodTotals(income: 0, expense: 0);
    final lastMonth =
        ref.watch(monthTotalsProvider(DateTime(now.year, now.month - 1))).value ?? const PeriodTotals(income: 0, expense: 0);
    final budgets = ref.watch(budgetUsageProvider(now));
    final budgetTotal = budgets.fold<int>(0, (s, b) => s + b.budget.limitAmount);

    String incomeNote() {
      if (lastMonth.income == 0) return 'bulan ini';
      final d = ((month.income - lastMonth.income) / lastMonth.income * 100).round();
      return '${d >= 0 ? '+' : ''}$d% vs bln lalu';
    }

    String expenseNote() {
      if (budgetTotal > 0) return '${(month.expense / budgetTotal * 100).round()}% dari budget';
      if (lastMonth.expense == 0) return 'bulan ini';
      final d = ((month.expense - lastMonth.expense) / lastMonth.expense * 100).round();
      return '${d >= 0 ? '+' : ''}$d% vs bln lalu';
    }

    return NeuPressable(
      onTap: () => context.push('/wallets'),
      restDepth: 1,
      pressedDepth: 0.2,
      pressedScale: 0.985,
      haptic: false,
      radius: AuraRadius.xl,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AuraRadius.xl),
        child: Stack(
          children: [
            const Positioned.fill(child: RepaintBoundary(child: _DriftingBlobs())),
            Padding(
              padding: const EdgeInsets.all(AuraSpace.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('Total Kekayaan Bersih', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                      const Spacer(),
                      if (month.net != 0)
                        NeuSurface(
                          depth: -0.6,
                          radius: AuraRadius.pill,
                          color: month.net >= 0 ? p.tertiaryFixed : p.secondaryFixed,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AuraIcon(
                                month.net >= 0 ? HugeIcons.strokeRoundedArrowUp01 : HugeIcons.strokeRoundedArrowDown01,
                                size: 14,
                                strokeWidth: 2.2,
                                color: month.net >= 0 ? p.onTertiaryFixed : p.secondary,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                hidden ? '•••' : Rupiah.compact(month.net.abs()),
                                style: AuraType.labelSm.copyWith(color: month.net >= 0 ? p.onTertiaryFixed : p.secondary),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  MoneyText(netWorth, hidden: hidden, style: AuraType.currency.copyWith(color: p.onSurface)),
                  const SizedBox(height: 2),
                  Text(
                    wallets.isEmpty ? 'Belum ada dompet — ketuk untuk menambah' : 'Dari ${wallets.length} dompet',
                    style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                  ),
                  const SizedBox(height: AuraSpace.md),
                  Row(
                    children: [
                      Expanded(
                        child: _Meter(
                          label: 'Pemasukan',
                          value: month.income,
                          note: incomeNote(),
                          hidden: hidden,
                          icon: HugeIcons.strokeRoundedArrowDown01,
                          chip: p.tertiaryFixed,
                          ink: p.onTertiaryFixed,
                          noteColor: p.tertiary,
                        ),
                      ),
                      const SizedBox(width: AuraSpace.md),
                      Expanded(
                        child: _Meter(
                          label: 'Pengeluaran',
                          value: month.expense,
                          note: expenseNote(),
                          hidden: hidden,
                          icon: HugeIcons.strokeRoundedArrowUp01,
                          chip: p.secondaryFixed,
                          ink: p.secondary,
                          noteColor: p.secondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dua gumpalan warna blur yang bergerak perlahan di latar kartu utama.
class _DriftingBlobs extends StatefulWidget {
  const _DriftingBlobs();

  @override
  State<_DriftingBlobs> createState() => _DriftingBlobsState();
}

class _DriftingBlobsState extends State<_DriftingBlobs> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 14))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final a = _c.value * math.pi * 2;
          return Stack(
            children: [
              Positioned(
                right: -40 + math.cos(a) * 18,
                top: -40 + math.sin(a) * 14,
                child: _blob(p.primaryContainer.withValues(alpha: p.isDark ? 0.18 : 0.14), 170),
              ),
              Positioned(
                left: -40 + math.sin(a) * 16,
                bottom: -50 + math.cos(a) * 12,
                child: _blob(p.tertiaryContainer.withValues(alpha: p.isDark ? 0.2 : 0.2), 170),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _blob(Color c, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)]),
        ),
      );
}

class _Meter extends StatelessWidget {
  const _Meter({
    required this.label,
    required this.value,
    required this.note,
    required this.hidden,
    required this.icon,
    required this.chip,
    required this.ink,
    required this.noteColor,
  });
  final String label;
  final int value;
  final String note;
  final bool hidden;
  final HugeIconData icon;
  final Color chip;
  final Color ink;
  final Color noteColor;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuSurface(
      depth: -1,
      radius: AuraRadius.md,
      color: p.surfaceContainer,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(color: chip, shape: BoxShape.circle),
                child: Center(child: AuraIcon(icon, size: 12, color: ink, strokeWidth: 2.4)),
              ),
              const SizedBox(width: 6),
              Text(label, style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 4),
          MoneyText(value, hidden: hidden, style: AuraType.labelLg.copyWith(color: p.onSurface, fontWeight: FontWeight.w700)),
          Text(note, style: AuraType.labelSm.copyWith(color: noteColor, fontWeight: FontWeight.w600), maxLines: 1),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions();

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final actions = [
      ('Keluar', HugeIcons.strokeRoundedMoneySend01, p.primaryFixed, p.primary, () => showAddTxSheet(context, kind: TxKind.expense)),
      ('Masuk', HugeIcons.strokeRoundedMoneyReceive01, p.tertiaryFixed, p.tertiary, () => showAddTxSheet(context, kind: TxKind.income)),
      (
        'Transfer',
        HugeIcons.strokeRoundedArrowDataTransferHorizontal,
        p.secondaryFixed,
        p.secondary,
        () => showAddTxSheet(context, kind: TxKind.transfer),
      ),
      ('Tagihan', HugeIcons.strokeRoundedInvoice03, p.surfaceHigh, p.onSurfaceVariant, () => context.push('/bills')),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (label, icon, bg, ink, onTap) in actions)
          _ActionTile(label: label, icon: icon, bg: bg, ink: ink, onTap: onTap),
      ],
    );
  }
}

class _ActionTile extends StatefulWidget {
  const _ActionTile({required this.label, required this.icon, required this.bg, required this.ink, required this.onTap});
  final String label;
  final HugeIconData icon;
  final Color bg;
  final Color ink;
  final VoidCallback onTap;

  @override
  State<_ActionTile> createState() => _ActionTileState();
}

class _ActionTileState extends State<_ActionTile> with SingleTickerProviderStateMixin {
  // Ikon "melompat" kecil setelah ditekan.
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void dispose() {
    _hop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      children: [
        NeuPressable(
          onTap: () {
            _hop.forward(from: 0);
            widget.onTap();
          },
          width: 68,
          height: 68,
          radius: 22,
          color: p.surfaceContainer,
          semanticLabel: widget.label,
          child: Center(
            child: AnimatedBuilder(
              animation: _hop,
              builder: (context, child) {
                final t = _hop.value;
                final y = -math.sin(t * math.pi) * 6 * (1 - t);
                return Transform.translate(offset: Offset(0, y), child: child);
              },
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: widget.bg.withValues(alpha: 0.7), borderRadius: BorderRadius.circular(14)),
                child: Center(child: AuraIcon(widget.icon, color: widget.ink, size: 22)),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(widget.label, style: AuraType.labelMd.copyWith(color: p.onSurface)),
      ],
    );
  }
}

class _CashflowCard extends ConsumerStatefulWidget {
  const _CashflowCard();

  @override
  ConsumerState<_CashflowCard> createState() => _CashflowCardState();
}

class _CashflowCardState extends ConsumerState<_CashflowCard> {
  int? _selected;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final period = ref.watch(flowPeriodProvider);
    final now = DateTime.now();
    final range = flowRange(period, now);
    final days = ref.watch(dailyFlowProvider(range)).value ?? const <DayFlow>[];
    final hidden = ref.watch(hideBalanceProvider);
    final buckets = bucketize(period, days);
    if (buckets.isEmpty) return const SizedBox(height: 260);
    final sel = (_selected ?? currentBucketIndex(period, now, buckets.length)).clamp(0, buckets.length - 1);
    final b = buckets[sel];
    final totalExpense = buckets.fold<int>(0, (s, x) => s + x.expense);
    final dayCount = math.max(1, days.where((d) => !d.day.isAfter(now)).length);

    return NeuSurface(
      radius: AuraRadius.xl,
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Arus Kas', style: AuraType.headlineSm.copyWith(color: p.onSurface)),
                    Text.rich(
                      TextSpan(
                        text: 'Rata-rata keluar harian ',
                        children: [
                          TextSpan(
                            text: hidden ? 'Rp •••' : Rupiah.compact((totalExpense / dayCount).round()),
                            style: TextStyle(fontWeight: FontWeight.w700, color: p.onSurface),
                          ),
                        ],
                      ),
                      style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          NeuSegmented<FlowPeriod>(
            value: period,
            options: const {FlowPeriod.week: 'Mingguan', FlowPeriod.month: 'Bulanan', FlowPeriod.year: 'Tahunan'},
            onChanged: (v) {
              setState(() => _selected = null);
              ref.read(flowPeriodProvider.notifier).set(v);
            },
          ),
          const SizedBox(height: AuraSpace.md),
          NeuSurface(
            depth: -1,
            radius: AuraRadius.md,
            color: p.surfaceContainer,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.3), end: Offset.zero).animate(a), child: c),
              ),
              child: Row(
                key: ValueKey('${period.name}-$sel'),
                children: [
                  Container(width: 9, height: 9, decoration: BoxDecoration(color: p.primaryContainer, shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(b.caption, style: AuraType.labelMd.copyWith(color: p.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  Text(
                    hidden ? '+•••' : Rupiah.compact(b.income, signed: true),
                    style: AuraType.labelSm.copyWith(color: p.tertiary, fontSize: 11),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    hidden ? '-•••' : Rupiah.compact(-b.expense),
                    style: AuraType.labelSm.copyWith(color: p.secondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          RepaintBoundary(child: FlowChart(buckets: buckets, selected: sel, onSelect: (i) => setState(() => _selected = i))),
          const SizedBox(height: AuraSpace.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _legend(p.tertiaryContainer, 'Pemasukan', p),
              const SizedBox(width: AuraSpace.lg),
              _legend(p.primaryContainer, 'Pengeluaran', p),
            ],
          ),
        ],
      ),
    );
  }

  Widget _legend(Color c, String label, AuraPalette p) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant)),
        ],
      );
}

class _UpcomingBills extends ConsumerWidget {
  const _UpcomingBills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final bills = (ref.watch(billsProvider).value ?? const <Bill>[]).where((b) => b.paidAt == null).toList();
    final hidden = ref.watch(hideBalanceProvider);
    final today = DateId.dateOnly(DateTime.now());
    final soon = bills.where((b) => b.dueDate.difference(today).inDays <= 7).take(2).toList();
    if (soon.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: AuraSpace.lg),
      child: NeuPressable(
        onTap: () => context.push('/bills'),
        radius: AuraRadius.lg,
        pressedScale: 0.98,
        padding: const EdgeInsets.all(AuraSpace.md),
        child: Column(
          children: [
            for (final b in soon)
              Padding(
                padding: EdgeInsets.only(bottom: b == soon.last ? 0 : 10),
                child: Row(
                  children: [
                    NeuSurface(
                      depth: -0.8,
                      radius: 14,
                      width: 44,
                      height: 44,
                      color: p.surfaceContainer,
                      child: Center(child: AuraIcon(HugeIcons.strokeRoundedInvoice03, color: p.primary)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(b.name, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                          Text(
                            _dueText(b.dueDate, today),
                            style: AuraType.bodySm.copyWith(color: b.dueDate.isBefore(today) ? p.error : p.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Text(hidden ? 'Rp •••' : Rupiah.format(b.amount), style: AuraType.labelLg.copyWith(color: p.onSurface)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _dueText(DateTime due, DateTime today) {
    final d = DateId.dateOnly(due).difference(today).inDays;
    if (d < 0) return 'Terlambat ${-d} hari';
    if (d == 0) return 'Jatuh tempo hari ini';
    if (d == 1) return 'Jatuh tempo besok';
    return 'Jatuh tempo $d hari lagi';
  }
}


/// Banner kondisi yang perlu perhatian: sinkron gagal & tagihan terlambat.
class _Banners extends ConsumerStatefulWidget {
  const _Banners();

  @override
  ConsumerState<_Banners> createState() => _BannersState();
}

class _BannersState extends ConsumerState<_Banners> {
  bool _hideOverdue = false;

  @override
  Widget build(BuildContext context) {
    final sync = ref.watch(syncControllerProvider);
    final today = DateId.dateOnly(DateTime.now());
    final overdue = (ref.watch(billsProvider).value ?? const <Bill>[]).where((b) => b.paidAt == null && b.dueDate.isBefore(today)).toList();
    return Column(
      children: [
        AuraBanner(
          visible: sync.enabled && sync.status == SyncStatus.error,
          tone: AuraTone.error,
          icon: HugeIcons.strokeRoundedRefresh,
          title: 'Sinkron gagal',
          message: 'Catatanmu aman di HP ini dan akan dikirim ulang.',
          actionLabel: 'Coba lagi',
          onAction: () => ref.read(syncControllerProvider.notifier).syncNow(),
        ),
        AuraBanner(
          visible: overdue.isNotEmpty && !_hideOverdue,
          tone: AuraTone.warning,
          icon: HugeIcons.strokeRoundedInvoice03,
          title: overdue.length == 1 ? '${overdue.first.name} terlambat' : '${overdue.length} tagihan terlambat',
          message: 'Tandai lunas supaya pengingatnya berhenti.',
          actionLabel: 'Lihat',
          onAction: () => context.push('/bills'),
          onDismiss: () => setState(() => _hideOverdue = true),
        ),
      ],
    );
  }
}
