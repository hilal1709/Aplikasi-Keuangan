import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';
import 'tx_tile.dart';

class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key, this.walletId});
  final String? walletId;

  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  String _search = '';
  Timer? _debounce;
  TxKind? _kind;
  late String? _walletId = widget.walletId;
  String? _member;
  DateTime _month = DateId.monthStart(DateTime.now());

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final db = ref.watch(dbProvider);
    final wallets = ref.watch(walletBalancesProvider).value ?? const [];
    final members = ref.watch(membersProvider).value ?? const [];
    final hidden = ref.watch(hideBalanceProvider);

    return AuraPage(
      title: 'Riwayat',
      subtitle: DateId.month(_month),
      actions: [
        NeuIconButton(HugeIcons.strokeRoundedArrowLeft01, label: 'Bulan sebelumnya', onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
        NeuIconButton(
          HugeIcons.strokeRoundedArrowRight01,
          label: 'Bulan berikutnya',
          onTap: _month.isBefore(DateId.monthStart(DateTime.now())) ? () => setState(() => _month = DateTime(_month.year, _month.month + 1)) : null,
        ),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(AuraSpace.margin, AuraSpace.sm, AuraSpace.margin, AuraSpace.md),
          sliver: SliverToBoxAdapter(
            child: Column(
              children: [
                ShadInput(
                  placeholder: const Text('Cari catatan…'),
                  leading: const AuraIcon(HugeIcons.strokeRoundedSearch01, size: 18),
                  onChanged: (v) {
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 250), () => setState(() => _search = v));
                  },
                ),
                const SizedBox(height: AuraSpace.sm + 4),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,
                    children: [
                      for (final (k, label) in [(null, 'Semua'), (TxKind.expense, 'Keluar'), (TxKind.income, 'Masuk'), (TxKind.transfer, 'Transfer')])
                        _Chip(label: label, active: _kind == k, onTap: () => setState(() => _kind = k)),
                      _divider(p),
                      for (final w in wallets)
                        _Chip(
                          label: w.wallet.name,
                          dot: Color(w.wallet.color),
                          active: _walletId == w.wallet.id,
                          onTap: () => setState(() => _walletId = _walletId == w.wallet.id ? null : w.wallet.id),
                        ),
                      if (members.length > 1) ...[
                        _divider(p),
                        for (final m in members)
                          _Chip(
                            label: m.displayName,
                            dot: Color(m.color),
                            active: _member == m.userId,
                            onTap: () => setState(() => _member = _member == m.userId ? null : m.userId),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        StreamBuilder<List<TxEntry>>(
          stream: db.watchTx(
            from: _month,
            to: DateId.nextMonthStart(_month),
            kind: _kind,
            walletId: _walletId,
            createdBy: _member,
            search: _search,
          ),
          builder: (context, snap) {
            final rows = snap.data;
            if (rows == null) return const SliverToBoxAdapter(child: SizedBox(height: 200));
            if (rows.isEmpty) {
              return SliverToBoxAdapter(
                child: ClayEmpty(
                  kind: ClayKind.search,
                  title: _search.isEmpty && _kind == null && _walletId == null ? 'Bulan ini masih kosong' : 'Tidak ada yang cocok',
                  message: _search.isEmpty && _kind == null && _walletId == null
                      ? 'Transaksi yang kamu catat akan muncul di sini, dikelompokkan per hari.'
                      : 'Coba ubah kata kunci atau filter.',
                ),
              );
            }
            final groups = <DateTime, List<TxEntry>>{};
            for (final t in rows) {
              groups.putIfAbsent(DateId.dateOnly(t.occurredAt), () => []).add(t);
            }
            final entries = groups.entries.toList();
            var index = 0;
            return SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
              sliver: SliverList.list(
                children: [
                  for (final e in entries) ...[
                    _DayHeader(day: e.key, txs: e.value, hidden: hidden).staggerIn(index++, stepMs: 30),
                    for (final t in e.value)
                      Padding(padding: const EdgeInsets.only(bottom: 12), child: TxTile(t, showDate: false).staggerIn(index++, stepMs: 30)),
                    const SizedBox(height: AuraSpace.sm),
                  ],
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _divider(AuraPalette p) => Container(
        width: 1,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        color: p.outlineVariant,
      );
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.txs, required this.hidden});
  final DateTime day;
  final List<TxEntry> txs;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final net = txs.fold<int>(0, (s, t) => s + switch (t.kind) { TxKind.income => t.amount, TxKind.expense => -t.amount, TxKind.transfer => 0 });
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
      child: Row(
        children: [
          Text(DateId.relativeDay(day), style: AuraType.labelLg.copyWith(color: p.onSurface)),
          const SizedBox(width: 6),
          Text(DateId.dayLong(day), style: AuraType.bodySm.copyWith(color: p.outline)),
          const Spacer(),
          Text(
            hidden ? 'Rp •••' : Rupiah.format(net, signed: true),
            style: AuraType.labelMd.copyWith(color: net >= 0 ? p.tertiary : p.secondary),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.active, required this.onTap, this.dot});
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? dot;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: NeuPressable(
        onTap: onTap,
        restDepth: active ? -0.8 : 0.7,
        pressedDepth: -0.8,
        radius: AuraRadius.pill,
        color: active ? p.surfaceContainer : p.surfaceLow,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dot != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label, style: AuraType.labelMd.copyWith(color: active ? p.primary : p.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
