import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';
import '../../domain/finance_math.dart';
import '../../services/notifications.dart';
import '../../services/realtime.dart';

class BillsPage extends ConsumerWidget {
  const BillsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final all = ref.watch(billsProvider).value;
    final unpaid = (all ?? const <Bill>[]).where((b) => b.paidAt == null).toList();
    final monthStart = DateId.monthStart(DateTime.now());
    final paid = (all ?? const <Bill>[]).where((b) => b.paidAt != null && !b.paidAt!.isBefore(monthStart)).toList();
    final hidden = ref.watch(hideBalanceProvider);
    final dueTotal = unpaid.fold<int>(0, (s, b) => s + b.amount);

    var i = 0;
    return AuraPage(
      title: 'Tagihan',
      subtitle: 'Pengingat dikirim sebelum jatuh tempo',
      actions: [NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Tambah tagihan', color: p.primary, onTap: () => showBillForm(context))],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverList.list(
            children: [
              if (all != null && all.isEmpty)
                ClayEmpty(
                  kind: ClayKind.calendar,
                  title: 'Tidak ada tagihan',
                  message: 'Catat listrik, internet, kos, atau cicilan. Kami ingatkan beberapa hari sebelumnya.',
                  action: ShadButton(onPressed: () => showBillForm(context), child: const Text('Tambah tagihan')),
                )
              else ...[
                if (unpaid.isNotEmpty)
                  NeuSurface(
                    depth: -1,
                    radius: AuraRadius.lg,
                    color: p.surfaceContainer,
                    padding: const EdgeInsets.all(AuraSpace.md),
                    child: Row(
                      children: [
                        Text('${unpaid.length} belum dibayar', style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant)),
                        const Spacer(),
                        MoneyText(dueTotal, hidden: hidden, style: AuraType.headlineSm.copyWith(color: p.onSurface)),
                      ],
                    ),
                  ).staggerIn(i++),
                const SizedBox(height: AuraSpace.lg),
                for (final b in unpaid)
                  Padding(padding: const EdgeInsets.only(bottom: AuraSpace.md), child: _BillTile(bill: b, hidden: hidden).staggerIn(i++)),
                if (paid.isNotEmpty) ...[
                  const SizedBox(height: AuraSpace.sm),
                  const SectionHeader('Lunas bulan ini').staggerIn(i++),
                  const SizedBox(height: AuraSpace.sm + 4),
                  for (final b in paid)
                    Padding(padding: const EdgeInsets.only(bottom: AuraSpace.md), child: _BillTile(bill: b, hidden: hidden).staggerIn(i++)),
                ],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BillTile extends ConsumerWidget {
  const _BillTile({required this.bill, required this.hidden});
  final Bill bill;
  final bool hidden;

  Future<void> _pay(BuildContext context, WidgetRef ref) async {
    final db = ref.read(dbProvider);
    final owner = ownerStamp(ref);
    final now = DateTime.now();
    if (bill.walletId != null) {
      await db.upsertTx(TxEntriesCompanion.insert(
        id: newId(),
        kind: TxKind.expense,
        amount: bill.amount,
        walletId: bill.walletId!,
        categoryId: Value(bill.categoryId),
        note: Value(bill.name),
        occurredAt: now,
        billId: Value(bill.id),
        householdId: Value(bill.householdId ?? owner.householdId),
        createdBy: Value(owner.userId),
      ));
    }
    await db.upsertBill(bill.toCompanion(true).copyWith(paidAt: Value(now)));
    if (bill.repeatMonthly) {
      await db.upsertBill(BillsCompanion.insert(
        id: newId(),
        name: bill.name,
        amount: bill.amount,
        dueDate: advance(bill.dueDate, Frequency.monthly),
        remindDaysBefore: Value(bill.remindDaysBefore),
        repeatMonthly: const Value(true),
        walletId: Value(bill.walletId),
        categoryId: Value(bill.categoryId),
        householdId: Value(bill.householdId ?? owner.householdId),
        createdBy: Value(owner.userId),
      ));
    }
    HapticFeedback.heavyImpact();
    await ref.read(notificationsProvider).rescheduleBills();
    final who = ref.read(displayNameProvider).trim().split(' ').first;
    ref.read(realtimeProvider.notifier).notify(
          kind: 'bill',
          title: 'Tagihan ${bill.name} lunas',
          body: '${Rupiah.format(bill.amount)}${who.isEmpty ? '' : ' · dibayar $who'}',
        );
    if (context.mounted) {
      AuraToast.success(
        context,
        '${bill.name} lunas',
        message: bill.walletId == null ? 'Ditandai lunas tanpa mencatat pengeluaran.' : 'Pengeluaran otomatis dicatat.',
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final paid = bill.paidAt != null;
    final today = DateId.dateOnly(DateTime.now());
    final days = DateId.dateOnly(bill.dueDate).difference(today).inDays;
    final (dueText, dueColor) = paid
        ? ('Dibayar ${DateId.short(bill.paidAt!)}', p.tertiary)
        : days < 0
            ? ('Terlambat ${-days} hari', p.error)
            : days == 0
                ? ('Hari ini', p.primary)
                : days <= bill.remindDaysBefore
                    ? ('$days hari lagi', p.secondary)
                    : (DateId.short(bill.dueDate), p.onSurfaceVariant);

    return Opacity(
      opacity: paid ? 0.7 : 1,
      child: NeuPressable(
        onTap: paid ? null : () => showBillForm(context, existing: bill),
        radius: AuraRadius.lg,
        pressedScale: 0.98,
        padding: const EdgeInsets.all(AuraSpace.md),
        child: Row(
          children: [
            NeuSurface(
              depth: -0.8,
              radius: 16,
              width: 52,
              height: 56,
              color: p.surfaceContainer,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('${bill.dueDate.day}', style: AuraType.headlineSm.copyWith(color: dueColor, height: 1)),
                  Text(DateId.month(bill.dueDate).substring(0, 3).toUpperCase(), style: AuraType.labelSm.copyWith(color: p.outline)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(bill.name, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                  Text(dueText, style: AuraType.bodySm.copyWith(color: dueColor)),
                  Text(hidden ? 'Rp •••' : Rupiah.format(bill.amount), style: AuraType.labelMd.copyWith(color: p.onSurface)),
                ],
              ),
            ),
            if (!paid)
              NeuPressable(
                onTap: () => _pay(context, ref),
                radius: AuraRadius.pill,
                color: p.tertiaryFixed,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    // Centang: menandai tagihan lunas.
                    AuraIcon(HugeIcons.strokeRoundedTick02, size: 16, color: p.onTertiaryFixed, strokeWidth: 2.2),
                    const SizedBox(width: 4),
                    Text('Lunas', style: AuraType.labelMd.copyWith(color: p.onTertiaryFixed)),
                  ],
                ),
              )
            else
              AuraIcon(HugeIcons.strokeRoundedCheckmarkCircle02, color: p.tertiary),
          ],
        ),
      ),
    );
  }
}

Future<void> showBillForm(BuildContext context, {Bill? existing}) =>
    showFormSheet<void>(context, title: existing == null ? 'Tagihan baru' : 'Ubah tagihan', builder: (_) => _BillForm(existing: existing));

class _BillForm extends ConsumerStatefulWidget {
  const _BillForm({this.existing});
  final Bill? existing;

  @override
  ConsumerState<_BillForm> createState() => _BillFormState();
}

class _BillFormState extends ConsumerState<_BillForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _amount = widget.existing?.amount ?? 0;
  late DateTime _due = widget.existing?.dueDate ?? DateId.dateOnly(DateTime.now()).add(const Duration(days: 7));
  late int _remind = widget.existing?.remindDaysBefore ?? 3;
  late bool _repeat = widget.existing?.repeatMonthly ?? true;
  late String? _walletId = widget.existing?.walletId;
  late String? _categoryId = widget.existing?.categoryId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _amount <= 0) {
      AuraToast.error(context, 'Isi nama dan nominal tagihan');
      return;
    }
    final e = widget.existing;
    final owner = ownerStamp(ref);
    await ref.read(dbProvider).upsertBill(BillsCompanion(
          id: Value(e?.id ?? newId()),
          householdId: Value(e?.householdId ?? owner.householdId),
          createdBy: Value(e?.createdBy ?? owner.userId),
          createdAt: Value(e?.createdAt ?? DateTime.now()),
          name: Value(_name.text.trim()),
          amount: Value(_amount),
          dueDate: Value(_due),
          remindDaysBefore: Value(_remind),
          repeatMonthly: Value(_repeat),
          walletId: Value(_walletId),
          categoryId: Value(_categoryId),
          paidAt: Value(e?.paidAt),
        ));
    await ref.read(notificationsProvider).requestPermission();
    await ref.read(notificationsProvider).rescheduleBills();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final wallets = ref.watch(walletBalancesProvider).value ?? const [];
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => c.kind == CategoryKind.expense).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Nama tagihan'),
        ShadInput(controller: _name, placeholder: const Text('mis. Listrik PLN, IndiHome')),
        const FieldLabel('Nominal'),
        AmountField(initial: _amount, onChanged: (v) => _amount = v),
        const FieldLabel('Jatuh tempo'),
        NeuPressable(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _due,
              firstDate: DateTime.now().subtract(const Duration(days: 60)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
            );
            if (d != null) setState(() => _due = d);
          },
          radius: AuraRadius.md,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AuraIcon(HugeIcons.strokeRoundedCalendar03, size: 18, color: p.primary),
              const SizedBox(width: 8),
              Text(DateId.short(_due), style: AuraType.labelLg.copyWith(color: p.onSurface)),
            ],
          ),
        ),
        const FieldLabel('Ingatkan'),
        NeuSegmented<int>(
          value: _remind,
          options: const {1: 'H-1', 3: 'H-3', 7: 'H-7'},
          onChanged: (v) => setState(() => _remind = v),
        ),
        const FieldLabel('Bayar dari dompet (opsional)'),
        ShadSelect<String>(
          placeholder: const Text('Tanpa mencatat pengeluaran'),
          initialValue: _walletId,
          allowDeselection: true,
          onChanged: (v) => setState(() => _walletId = v),
          options: [for (final w in wallets) ShadOption(value: w.wallet.id, child: Text(w.wallet.name))],
          selectedOptionBuilder: (context, v) => Text(wallets.where((w) => w.wallet.id == v).firstOrNull?.wallet.name ?? ''),
        ),
        const FieldLabel('Kategori'),
        ShadSelect<String>(
          placeholder: const Text('Pilih kategori'),
          initialValue: _categoryId,
          onChanged: (v) => setState(() => _categoryId = v),
          options: [for (final c in cats) ShadOption(value: c.id, child: Text(c.name))],
          selectedOptionBuilder: (context, v) => Text(cats.where((c) => c.id == v).firstOrNull?.name ?? ''),
        ),
        const SizedBox(height: AuraSpace.md),
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ulangi tiap bulan', style: AuraType.labelLg.copyWith(color: p.onSurface)),
                  Text('Tagihan bulan depan dibuat saat ditandai lunas', style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                ],
              ),
            ),
            ShadSwitch(value: _repeat, onChanged: (v) => setState(() => _repeat = v)),
          ],
        ),
        PrimaryAction(label: 'Simpan', onPressed: _save),
        if (widget.existing != null)
          PrimaryAction(
            label: 'Hapus tagihan',
            destructive: true,
            onPressed: () async {
              await ref.read(dbProvider).softDeleteBill(widget.existing!.id);
              await ref.read(notificationsProvider).rescheduleBills();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}
