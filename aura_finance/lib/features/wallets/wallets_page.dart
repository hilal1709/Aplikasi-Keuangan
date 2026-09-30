import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/icons/category_icons.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/lottie.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';
import '../transactions/add_tx_sheet.dart';

const walletKindLabel = {
  WalletKind.cash: 'Tunai',
  WalletKind.bank: 'Rekening bank',
  WalletKind.ewallet: 'E-wallet',
  WalletKind.other: 'Lainnya',
};

const Map<WalletKind, HugeIconData> walletKindIcon = {
  WalletKind.cash: HugeIcons.strokeRoundedMoney03,
  WalletKind.bank: HugeIcons.strokeRoundedBank,
  WalletKind.ewallet: HugeIcons.strokeRoundedSmartPhone01,
  WalletKind.other: HugeIcons.strokeRoundedWallet01,
};

class WalletsPage extends ConsumerWidget {
  const WalletsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final wallets = ref.watch(walletBalancesProvider).value;
    final total = ref.watch(totalBalanceProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final archived = (ref.watch(allWalletsProvider).value ?? const <Wallet>[]).where((w) => w.archived).toList();

    return AuraPage(
      title: 'Dompet',
      subtitle: 'Saldo dihitung dari saldo awal + transaksi',
      actions: [
        NeuIconButton(HugeIcons.strokeRoundedArrowDataTransferHorizontal, label: 'Transfer', onTap: () => showAddTxSheet(context, kind: TxKind.transfer)),
        NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Tambah dompet', color: p.primary, onTap: () => showWalletForm(context, ref)),
      ],
      slivers: [
        if (wallets == null)
          const SliverToBoxAdapter(child: AuraLoadingView(label: 'Memuat dompet…'))
        else if (wallets.isEmpty)
          SliverToBoxAdapter(
            child: ClayEmpty(
              kind: ClayKind.wallet,
              title: 'Belum ada dompet',
              message: 'Tambahkan dompet tunai, rekening, atau e-wallet yang kamu pakai sehari-hari.',
              action: ShadButton(onPressed: () => showWalletForm(context, ref), child: const Text('Tambah dompet')),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(AuraSpace.margin, AuraSpace.sm, AuraSpace.margin, 0),
            sliver: SliverList.list(
              children: [
                NeuSurface(
                  depth: -1,
                  radius: AuraRadius.lg,
                  color: p.surfaceContainer,
                  padding: const EdgeInsets.all(AuraSpace.md),
                  child: Row(
                    children: [
                      Text('Total', style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant)),
                      const Spacer(),
                      MoneyText(total, hidden: hidden, style: AuraType.headlineSm.copyWith(color: p.onSurface)),
                    ],
                  ),
                ).staggerIn(0),
                const SizedBox(height: AuraSpace.lg),
                for (final (i, w) in wallets.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AuraSpace.md),
                    child: _WalletCard(w: w, hidden: hidden).staggerIn(i + 1),
                  ),
                Text(
                  'Ketuk dompet untuk melihat riwayat, tekan lama untuk mengubah atau menghapus.',
                  textAlign: TextAlign.center,
                  style: AuraType.bodySm.copyWith(color: p.outline),
                ),
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: AuraSpace.lg),
                  const SectionHeader('Diarsipkan'),
                  const SizedBox(height: AuraSpace.sm + 4),
                  for (final (i, w) in archived.indexed)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _ArchivedWallet(wallet: w).slideInX(i),
                    ),
                ],
                const SizedBox(height: AuraSpace.xl),
              ],
            ),
          ),
      ],
    );
  }
}

class _WalletCard extends ConsumerWidget {
  const _WalletCard({required this.w, required this.hidden});
  final WalletBalance w;
  final bool hidden;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final tone = Color(w.wallet.color);
    return NeuPressable(
      onTap: () => context.push('/history?wallet=${w.wallet.id}'),
      onLongPress: () => showWalletForm(context, ref, existing: w.wallet),
      radius: AuraRadius.lg,
      pressedScale: 0.98,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AuraRadius.lg),
        child: Stack(
          children: [
            // Aksen warna dompet: pita lembut di sisi kiri + cahaya di pojok.
            Positioned(
              right: -30,
              top: -30,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [tone.withValues(alpha: 0.22), tone.withValues(alpha: 0)]),
                ),
              ),
            ),
            Positioned(left: 0, top: 18, bottom: 18, child: Container(width: 4, decoration: BoxDecoration(color: tone, borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))))),
            Padding(
              padding: const EdgeInsets.fromLTRB(AuraSpace.lg, AuraSpace.md, AuraSpace.md, AuraSpace.md),
              child: Row(
                children: [
                  NeuSurface(
                    depth: -0.8,
                    radius: 16,
                    width: 48,
                    height: 48,
                    color: p.surfaceContainer,
                    child: Center(child: AuraIcon(walletKindIcon[w.wallet.kind]!, color: tone)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(w.wallet.name, style: AuraType.bodyLg.copyWith(color: p.onSurface, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(walletKindLabel[w.wallet.kind]!, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                            if (!w.wallet.isShared) ...[
                              const SizedBox(width: 6),
                              iconLabel(context, HugeIcons.strokeRoundedLockKey, 'Pribadi'),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  MoneyText(
                    w.balance,
                    hidden: hidden,
                    style: AuraType.labelLg.copyWith(color: w.balance < 0 ? p.error : p.onSurface, fontWeight: FontWeight.w700),
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

Future<void> showWalletForm(BuildContext context, WidgetRef ref, {Wallet? existing}) {
  return showFormSheet<void>(
    context,
    title: existing == null ? 'Dompet baru' : 'Ubah dompet',
    builder: (context) => _WalletForm(existing: existing),
  );
}

class _WalletForm extends ConsumerStatefulWidget {
  const _WalletForm({this.existing});
  final Wallet? existing;

  @override
  ConsumerState<_WalletForm> createState() => _WalletFormState();
}

class _WalletFormState extends ConsumerState<_WalletForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late WalletKind _kind = widget.existing?.kind ?? WalletKind.bank;
  late int _color = widget.existing?.color ?? categoryTones.first;
  late int _initial = widget.existing?.initialBalance ?? 0;
  late bool _shared = widget.existing?.isShared ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      AuraToast.error(context, 'Nama dompet belum diisi');
      return;
    }
    final e = widget.existing;
    final owner = ownerStamp(ref);
    await ref.read(dbProvider).upsertWallet(WalletsCompanion(
          id: Value(e?.id ?? newId()),
          householdId: Value(e?.householdId ?? owner.householdId),
          createdBy: Value(e?.createdBy ?? owner.userId),
          createdAt: Value(e?.createdAt ?? DateTime.now()),
          name: Value(_name.text.trim()),
          kind: Value(_kind),
          color: Value(_color),
          initialBalance: Value(_initial),
          isShared: Value(_shared),
          sortOrder: Value(e?.sortOrder ?? 0),
          archived: Value(e?.archived ?? false),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  /// Dompet kosong langsung dihapus; dompet bertransaksi diberi pilihan
  /// "arsipkan saja" (riwayat aman) atau "hapus beserta transaksinya".
  Future<void> _delete() async {
    final e = widget.existing!;
    final db = ref.read(dbProvider);
    final n = await db.countTxForWallet(e.id);
    if (!mounted) return;
    final choice = await showAuraModal<String>(
      context,
      title: 'Hapus dompet ${e.name}?',
      message: n == 0
          ? 'Dompet ini belum punya transaksi.'
          : 'Dompet ini punya $n transaksi. Arsipkan saja agar riwayat & laporan tetap utuh, atau hapus beserta transaksinya.',
      actions: [
        const AuraModalAction('Batal'),
        if (n > 0) const AuraModalAction('Arsipkan', value: 'archive', primary: true),
        AuraModalAction(n > 0 ? 'Hapus semua' : 'Hapus', value: 'delete', destructive: true),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'archive') {
      await db.upsertWallet(e.toCompanion(true).copyWith(archived: const Value(true)));
      if (mounted) AuraToast.success(context, 'Dompet diarsipkan', message: 'Riwayat transaksinya tetap tersimpan.');
    } else {
      await db.softDeleteWallet(e.id, withTransactions: true);
      if (mounted) AuraToast.success(context, 'Dompet dihapus', message: n > 0 ? '$n transaksi ikut dihapus.' : null);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Nama'),
        ShadInput(controller: _name, placeholder: const Text('mis. BCA, GoPay, Tunai'), textCapitalization: TextCapitalization.words),
        const FieldLabel('Jenis'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final k in WalletKind.values)
              NeuPressable(
                onTap: () => setState(() => _kind = k),
                restDepth: _kind == k ? -0.8 : 0.7,
                pressedDepth: -0.8,
                radius: AuraRadius.pill,
                color: _kind == k ? p.surfaceContainer : p.surfaceLow,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AuraIcon(walletKindIcon[k]!, size: 16, color: _kind == k ? p.primary : p.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(walletKindLabel[k]!, style: AuraType.labelMd.copyWith(color: _kind == k ? p.primary : p.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
        ),
        const FieldLabel('Saldo awal'),
        AmountField(initial: _initial, onChanged: (v) => _initial = v),
        const FieldLabel('Warna'),
        ToneSwatches(value: _color, onChanged: (c) => setState(() => _color = c)),
        ShareToggle(
          title: 'Dompet bersama',
          value: _shared,
          locked: widget.existing?.isShared == true,
          sharedHint: 'Saldo & transaksinya terlihat semua anggota',
          privateHint: 'Hanya kamu yang melihat saldo & transaksinya',
          onChanged: (v) => setState(() => _shared = v),
        ),
        PrimaryAction(label: 'Simpan', onPressed: _save),
        if (widget.existing != null) PrimaryAction(label: 'Hapus dompet', destructive: true, onPressed: _delete),
      ],
    );
  }
}

/// Dompet yang diarsipkan: tersembunyi dari daftar & formulir, tetapi riwayatnya utuh.
/// Bisa dipulihkan atau dihapus permanen dari sini.
class _ArchivedWallet extends ConsumerWidget {
  const _ArchivedWallet({required this.wallet});
  final Wallet wallet;

  Future<void> _options(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final n = await db.countTxForWallet(wallet.id);
    if (!context.mounted) return;
    final choice = await showAuraModal<String>(
      context,
      title: wallet.name,
      message: n == 0 ? 'Dompet ini diarsipkan dan tidak punya transaksi.' : 'Dompet ini diarsipkan. Riwayatnya ($n transaksi) masih tersimpan.',
      actions: [
        const AuraModalAction('Tutup'),
        const AuraModalAction('Pulihkan', value: 'restore', primary: true),
        AuraModalAction(n > 0 ? 'Hapus semua' : 'Hapus', value: 'delete', destructive: true),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice == 'restore') {
      await db.upsertWallet(wallet.toCompanion(true).copyWith(archived: const Value(false)));
      if (context.mounted) AuraToast.success(context, '${wallet.name} dipulihkan');
    } else {
      final ok = await confirmDelete(
        context,
        title: 'Hapus ${wallet.name}?',
        message: n > 0 ? '$n transaksi di dompet ini ikut dihapus.' : 'Dompet akan dihapus permanen.',
      );
      if (!ok) return;
      await db.softDeleteWallet(wallet.id, withTransactions: true);
      if (context.mounted) AuraToast.success(context, 'Dompet dihapus');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    return NeuPressable(
      onTap: () => _options(context, ref),
      radius: AuraRadius.md,
      pressedScale: 0.98,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: Color(wallet.color), shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(wallet.name, style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant))),
          iconLabel(context, HugeIcons.strokeRoundedArchive02, 'Diarsipkan'),
        ],
      ),
    );
  }
}
