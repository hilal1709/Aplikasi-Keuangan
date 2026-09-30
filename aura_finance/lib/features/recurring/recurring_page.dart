import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
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
import '../../core/widgets/lottie.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';

const frequencyLabel = {
  Frequency.daily: 'Harian',
  Frequency.weekly: 'Mingguan',
  Frequency.monthly: 'Bulanan',
  Frequency.yearly: 'Tahunan',
};

class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final rules = ref.watch(recurringProvider).value;
    final cats = ref.watch(categoryMapProvider);
    final wallets = ref.watch(walletMapProvider);
    final hidden = ref.watch(hideBalanceProvider);

    return AuraPage(
      title: 'Berulang',
      subtitle: 'Gaji, langganan, dan cicilan dicatat otomatis',
      actions: [NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Tambah', color: p.primary, onTap: () => showRecurringForm(context))],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverList.list(
            children: [
              if (rules == null)
                const AuraLoadingView(label: 'Memuat jadwal…')
              else if (rules.isEmpty)
                ClayEmpty(
                  kind: ClayKind.calendar,
                  title: 'Belum ada transaksi berulang',
                  message: 'Atur sekali, lalu Aura mencatatnya otomatis setiap jatuh tempo — bahkan saat aplikasi ditutup.',
                  action: ShadButton(onPressed: () => showRecurringForm(context), child: const Text('Tambah')),
                )
              else
                for (final (i, r) in rules.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AuraSpace.md),
                    child: Opacity(
                      opacity: r.active ? 1 : 0.55,
                      child: NeuPressable(
                        onTap: () => showRecurringForm(context, existing: r),
                        radius: AuraRadius.lg,
                        pressedScale: 0.98,
                        padding: const EdgeInsets.all(AuraSpace.md),
                        child: Row(
                          children: [
                            CategoryBadge(
                              icon: cats[r.categoryId]?.icon ?? (r.kind == TxKind.income ? 'salary' : 'subscription'),
                              color: cats[r.categoryId]?.color ?? p.primaryContainer.toARGB32(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r.note.isNotEmpty ? r.note : (cats[r.categoryId]?.name ?? 'Berulang'),
                                    style: AuraType.labelLg.copyWith(color: p.onSurface),
                                  ),
                                  Text(
                                    '${frequencyLabel[r.frequency]} • ${wallets[r.walletId]?.wallet.name ?? '—'} • berikutnya ${DateId.short(r.nextRun)}',
                                    style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              hidden ? 'Rp •••' : Rupiah.format(r.kind == TxKind.income ? r.amount : -r.amount, signed: true),
                              style: AuraType.labelLg.copyWith(color: r.kind == TxKind.income ? p.tertiary : p.secondary),
                            ),
                          ],
                        ),
                      ),
                    ).staggerIn(i),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

Future<void> showRecurringForm(BuildContext context, {RecurringRule? existing}) =>
    showFormSheet<void>(context, title: existing == null ? 'Transaksi berulang' : 'Ubah berulang', builder: (_) => _RecurringForm(existing: existing));

class _RecurringForm extends ConsumerStatefulWidget {
  const _RecurringForm({this.existing});
  final RecurringRule? existing;

  @override
  ConsumerState<_RecurringForm> createState() => _RecurringFormState();
}

class _RecurringFormState extends ConsumerState<_RecurringForm> {
  late TxKind _kind = widget.existing?.kind ?? TxKind.expense;
  late int _amount = widget.existing?.amount ?? 0;
  late String? _walletId = widget.existing?.walletId;
  late String? _categoryId = widget.existing?.categoryId;
  late Frequency _freq = widget.existing?.frequency ?? Frequency.monthly;
  late DateTime _next = widget.existing?.nextRun ?? DateId.dateOnly(DateTime.now()).add(const Duration(hours: 8));
  late bool _active = widget.existing?.active ?? true;
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_amount <= 0 || _walletId == null || _categoryId == null) {
      AuraToast.error(context, 'Lengkapi nominal, dompet, dan kategori');
      return;
    }
    final e = widget.existing;
    final owner = ownerStamp(ref);
    await ref.read(dbProvider).upsertRecurring(RecurringRulesCompanion(
          id: Value(e?.id ?? newId()),
          householdId: Value(e?.householdId ?? owner.householdId),
          createdBy: Value(e?.createdBy ?? owner.userId),
          createdAt: Value(e?.createdAt ?? DateTime.now()),
          kind: Value(_kind),
          amount: Value(_amount),
          walletId: Value(_walletId!),
          categoryId: Value(_categoryId),
          note: Value(_note.text.trim()),
          frequency: Value(_freq),
          nextRun: Value(_next),
          active: Value(_active),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final wallets = ref.watch(walletBalancesProvider).value ?? const [];
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == (_kind == TxKind.income ? CategoryKind.income : CategoryKind.expense))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeuSegmented<TxKind>(
          value: _kind,
          options: const {TxKind.expense: 'Pengeluaran', TxKind.income: 'Pemasukan'},
          onChanged: (k) => setState(() {
            _kind = k;
            _categoryId = null;
          }),
        ),
        const FieldLabel('Nama / catatan'),
        ShadInput(controller: _note, placeholder: const Text('mis. Gaji kantor, Netflix')),
        const FieldLabel('Nominal'),
        AmountField(initial: _amount, onChanged: (v) => _amount = v),
        const FieldLabel('Kategori'),
        ShadSelect<String>(
          key: ValueKey(_kind),
          placeholder: const Text('Pilih kategori'),
          initialValue: _categoryId,
          onChanged: (v) => setState(() => _categoryId = v),
          options: [for (final c in cats) ShadOption(value: c.id, child: Text(c.name))],
          selectedOptionBuilder: (context, v) => Text(cats.where((c) => c.id == v).firstOrNull?.name ?? ''),
        ),
        const FieldLabel('Dompet'),
        ShadSelect<String>(
          placeholder: const Text('Pilih dompet'),
          initialValue: _walletId,
          onChanged: (v) => setState(() => _walletId = v),
          options: [for (final w in wallets) ShadOption(value: w.wallet.id, child: Text(w.wallet.name))],
          selectedOptionBuilder: (context, v) => Text(wallets.where((w) => w.wallet.id == v).firstOrNull?.wallet.name ?? ''),
        ),
        const FieldLabel('Frekuensi'),
        NeuSegmented<Frequency>(
          value: _freq,
          options: const {Frequency.weekly: 'Mingguan', Frequency.monthly: 'Bulanan', Frequency.yearly: 'Tahunan'},
          onChanged: (f) => setState(() => _freq = f),
        ),
        const FieldLabel('Tanggal berikutnya'),
        NeuPressable(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _next,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
            );
            if (d != null) setState(() => _next = DateTime(d.year, d.month, d.day, 8));
          },
          radius: AuraRadius.md,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AuraIcon(HugeIcons.strokeRoundedCalendar03, size: 18, color: p.primary),
              const SizedBox(width: 8),
              Text(DateId.short(_next), style: AuraType.labelLg.copyWith(color: p.onSurface)),
            ],
          ),
        ),
        if (widget.existing != null) ...[
          const SizedBox(height: AuraSpace.md),
          Row(
            children: [
              Expanded(child: Text('Aktif', style: AuraType.labelLg.copyWith(color: p.onSurface))),
              ShadSwitch(value: _active, onChanged: (v) => setState(() => _active = v)),
            ],
          ),
        ],
        PrimaryAction(label: 'Simpan', onPressed: _save),
        if (widget.existing != null)
          PrimaryAction(
            label: 'Hapus',
            destructive: true,
            onPressed: () async {
              await ref.read(dbProvider).softDeleteRecurring(widget.existing!.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
      ],
    );
  }
}
