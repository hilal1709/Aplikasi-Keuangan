import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';

import '../../core/widgets/feedback.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';
import 'add_tx_sheet.dart';

/// Baris transaksi: ketuk untuk edit, geser ke kiri untuk hapus (dengan "Urungkan").
class TxTile extends ConsumerWidget {
  const TxTile(this.tx, {super.key, this.showDate = true});
  final TxEntry tx;
  final bool showDate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final cat = ref.watch(categoryMapProvider)[tx.categoryId];
    final wallets = ref.watch(walletMapProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final by = members.where((m) => m.userId == tx.createdBy).firstOrNull;

    final (title, iconKey, tone) = switch (tx.kind) {
      TxKind.transfer => ('Transfer', 'receive', p.secondary.toARGB32()),
      _ => (cat?.name ?? 'Tanpa kategori', cat?.icon ?? 'other', cat?.color ?? p.outline.toARGB32()),
    };
    final walletName = wallets[tx.walletId]?.wallet.name ?? '—';
    final subtitleParts = [
      if (showDate) '${DateId.relativeDay(tx.occurredAt)}, ${DateId.time(tx.occurredAt)}' else DateId.time(tx.occurredAt),
      if (tx.kind == TxKind.transfer) '$walletName → ${wallets[tx.toWalletId]?.wallet.name ?? '—'}' else walletName,
    ];
    final amountColor = switch (tx.kind) {
      TxKind.income => p.tertiary,
      TxKind.expense => p.secondary,
      TxKind.transfer => p.onSurfaceVariant,
    };
    final signed = switch (tx.kind) {
      TxKind.income => tx.amount,
      TxKind.expense => -tx.amount,
      TxKind.transfer => tx.amount,
    };

    return Dismissible(
      key: ValueKey('tx-${tx.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      onUpdate: (d) {
        if (d.reached && !d.previousReached) HapticFeedback.mediumImpact();
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(color: p.secondaryFixed, borderRadius: BorderRadius.circular(AuraRadius.md)),
        child: AuraIcon(HugeIcons.strokeRoundedDelete02, color: p.secondary),
      ),
      onDismissed: (_) async {
        final db = ref.read(dbProvider);
        await db.softDeleteTx(tx.id);
        if (!context.mounted) return;
        AuraToast.show(
          context,
          title: 'Transaksi dihapus',
          message: tx.note.isNotEmpty ? tx.note : null,
          tone: AuraTone.warning,
          actionLabel: 'Urungkan',
          onAction: () => db.restoreTx(tx.id),
          duration: const Duration(seconds: 5),
        );
      },
      child: NeuPressable(
        onTap: () => showAddTxSheet(context, existing: tx),
        radius: AuraRadius.md,
        pressedScale: 0.98,
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            CategoryBadge(icon: iconKey, color: tone),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tx.note.isNotEmpty ? tx.note : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuraType.bodyLg.copyWith(color: p.onSurface, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    [if (tx.note.isNotEmpty) title, ...subtitleParts].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                hidden
                    ? Text('Rp •••', style: AuraType.labelLg.copyWith(color: amountColor))
                    : Text(
                        Rupiah.format(signed, signed: tx.kind == TxKind.income),
                        style: AuraType.labelLg.copyWith(color: amountColor, fontWeight: FontWeight.w700),
                      ),
                if (by != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(by.displayName, style: AuraType.labelSm.copyWith(color: p.outline)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
