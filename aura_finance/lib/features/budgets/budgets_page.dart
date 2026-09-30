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
import '../insights/insights_providers.dart';

class BudgetsPage extends ConsumerStatefulWidget {
  const BudgetsPage({super.key});

  @override
  ConsumerState<BudgetsPage> createState() => _BudgetsPageState();
}

class _BudgetsPageState extends ConsumerState<BudgetsPage> {
  DateTime _month = DateId.monthStart(DateTime.now());

  Future<void> _copyLastMonth() async {
    final db = ref.read(dbProvider);
    final prev = DateTime(_month.year, _month.month - 1);
    final last = await db.watchBudgets(prev).first;
    if (last.isEmpty) {
      if (mounted) AuraToast.info(context, 'Bulan lalu belum ada budget');
      return;
    }
    final existing = (await db.watchBudgets(_month).first).map((b) => b.categoryId).toSet();
    final owner = ownerStamp(ref);
    for (final b in last.where((b) => !existing.contains(b.categoryId))) {
      await db.upsertBudget(BudgetsCompanion.insert(
        id: newId(),
        categoryId: b.categoryId,
        month: _month,
        limitAmount: b.limitAmount,
        householdId: Value(owner.householdId),
        createdBy: Value(owner.userId),
        isShared: Value(b.isShared),
      ));
    }
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final usage = ref.watch(budgetUsageProvider(_month));
    final hidden = ref.watch(hideBalanceProvider);
    final totalLimit = usage.fold<int>(0, (s, u) => s + u.budget.limitAmount);
    final totalSpent = usage.fold<int>(0, (s, u) => s + u.spent);
    final isCurrent = _month == DateId.monthStart(DateTime.now());
    final daysLeft = isCurrent ? DateId.nextMonthStart(_month).difference(DateId.dateOnly(DateTime.now())).inDays : 0;

    return AuraPage(
      title: 'Budget',
      subtitle: DateId.month(_month),
      actions: [
        NeuIconButton(HugeIcons.strokeRoundedArrowLeft01, label: 'Bulan sebelumnya', onTap: () => setState(() => _month = DateTime(_month.year, _month.month - 1))),
        NeuIconButton(HugeIcons.strokeRoundedArrowRight01, label: 'Bulan berikutnya', onTap: () => setState(() => _month = DateTime(_month.year, _month.month + 1))),
        NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Tambah budget', color: p.primary, onTap: () => _showBudgetForm(context, ref, _month)),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverList.list(
            children: [
              if (usage.isEmpty)
                ClayEmpty(
                  kind: ClayKind.calendar,
                  title: 'Belum ada budget bulan ini',
                  message: 'Batasi pengeluaran per kategori. Kami beri tahu saat pemakaian mencapai 80% dan 100%.',
                  action: Wrap(
                    spacing: 8,
                    children: [
                      ShadButton(onPressed: () => _showBudgetForm(context, ref, _month), child: const Text('Buat budget')),
                      ShadButton.outline(onPressed: _copyLastMonth, child: const Text('Salin bulan lalu')),
                    ],
                  ),
                )
              else ...[
                NeuSurface(
                  radius: AuraRadius.xl,
                  padding: const EdgeInsets.all(AuraSpace.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Terpakai', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          MoneyText(totalSpent, hidden: hidden, style: AuraType.headlineLg.copyWith(color: p.onSurface)),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              hidden ? '/ Rp •••' : '/ ${Rupiah.compact(totalLimit)}',
                              style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AuraSpace.sm + 4),
                      NeuProgress(value: totalLimit == 0 ? 0 : totalSpent / totalLimit, height: 14, warn: totalSpent > totalLimit * 0.8),
                      if (isCurrent) ...[
                        const SizedBox(height: AuraSpace.sm),
                        Text(
                          totalSpent >= totalLimit
                              ? 'Budget total sudah terlampaui.'
                              : hidden
                                  ? '$daysLeft hari lagi'
                                  : 'Aman dipakai ${Rupiah.compact(((totalLimit - totalSpent) / (daysLeft == 0 ? 1 : daysLeft)).round())}/hari selama $daysLeft hari lagi',
                          style: AuraType.bodySm.copyWith(color: totalSpent >= totalLimit ? p.error : p.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                ).staggerIn(0),
                const SizedBox(height: AuraSpace.lg),
                for (final (i, u) in usage.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AuraSpace.md),
                    child: _BudgetTile(
                      u: u,
                      hidden: hidden,
                      showShare: ref.watch(householdIdProvider) != null,
                      onTap: () => _showBudgetForm(context, ref, _month, existing: u.budget),
                    ).staggerIn(i + 1),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({required this.u, required this.hidden, required this.onTap, this.showShare = false});
  final BudgetUsage u;
  final bool hidden;
  final bool showShare;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final c = u.category;
    final left = u.budget.limitAmount - u.spent;
    return NeuPressable(
      onTap: onTap,
      radius: AuraRadius.lg,
      pressedScale: 0.98,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              CategoryBadge(icon: c?.icon ?? 'other', color: c?.color ?? p.outline.toARGB32(), size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(c?.name ?? 'Kategori terhapus', style: AuraType.labelLg.copyWith(color: p.onSurface), overflow: TextOverflow.ellipsis)),
                        if (showShare) ...[const SizedBox(width: 6), ShareBadge(shared: u.budget.isShared)],
                      ],
                    ),
                    Text(
                      hidden
                          ? 'Rp ••• dari Rp •••'
                          : '${Rupiah.compact(u.spent)} dari ${Rupiah.compact(u.budget.limitAmount)}',
                      style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Text(
                u.over ? (hidden ? 'Lebih' : 'Lebih ${Rupiah.compact(-left)}') : (hidden ? 'Sisa' : 'Sisa ${Rupiah.compact(left)}'),
                style: AuraType.labelMd.copyWith(color: u.over ? p.error : (u.ratio >= 0.8 ? p.secondary : p.tertiary)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          NeuProgress(value: u.ratio, warn: u.ratio >= 0.8),
        ],
      ),
    );
  }
}

Future<void> _showBudgetForm(BuildContext context, WidgetRef ref, DateTime month, {Budget? existing}) {
  return showFormSheet<void>(
    context,
    title: existing == null ? 'Budget baru' : 'Ubah budget',
    builder: (_) => _BudgetForm(month: month, existing: existing),
  );
}

class _BudgetForm extends ConsumerStatefulWidget {
  const _BudgetForm({required this.month, this.existing});
  final DateTime month;
  final Budget? existing;

  @override
  ConsumerState<_BudgetForm> createState() => _BudgetFormState();
}

class _BudgetFormState extends ConsumerState<_BudgetForm> {
  late String? _categoryId = widget.existing?.categoryId;
  late int _limit = widget.existing?.limitAmount ?? 0;
  late bool _shared = widget.existing?.isShared ?? true;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => c.kind == CategoryKind.expense).toList();
    // Satu kategori boleh punya satu budget bersama dan satu budget pribadi.
    final taken = (ref.watch(budgetsProvider(widget.month)).value ?? const <Budget>[])
        .where((b) => b.id != widget.existing?.id && b.isShared == _shared)
        .map((b) => b.categoryId)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Kategori'),
        ShadSelect<String>(
          placeholder: const Text('Pilih kategori pengeluaran'),
          initialValue: _categoryId,
          onChanged: (v) => setState(() => _categoryId = v),
          options: [
            for (final c in cats.where((c) => !taken.contains(c.id)))
              ShadOption(value: c.id, child: Row(children: [CategoryBadge(icon: c.icon, color: c.color, size: 28), const SizedBox(width: 10), Text(c.name)])),
          ],
          selectedOptionBuilder: (context, v) => Text(cats.where((c) => c.id == v).firstOrNull?.name ?? ''),
        ),
        const FieldLabel('Batas per bulan'),
        AmountField(initial: _limit, onChanged: (v) => _limit = v),
        if (ref.watch(householdIdProvider) != null)
          ShareToggle(
            title: 'Budget bersama',
            value: _shared,
            locked: widget.existing?.isShared == true,
            sharedHint: 'Menghitung pengeluaran dari dompet bersama',
            privateHint: 'Menghitung pengeluaran dari dompet pribadimu saja',
            onChanged: (v) => setState(() {
              _shared = v;
              _categoryId = null;
            }),
          ),
        PrimaryAction(
          label: 'Simpan',
          onPressed: () async {
            if (_categoryId == null || _limit <= 0) {
              AuraToast.error(context, 'Pilih kategori dan isi batasnya');
              return;
            }
            final e = widget.existing;
            final owner = ownerStamp(ref);
            await ref.read(dbProvider).upsertBudget(BudgetsCompanion(
                  id: Value(e?.id ?? newId()),
                  householdId: Value(e?.householdId ?? owner.householdId),
                  createdBy: Value(e?.createdBy ?? owner.userId),
                  createdAt: Value(e?.createdAt ?? DateTime.now()),
                  categoryId: Value(_categoryId!),
                  month: Value(widget.month),
                  limitAmount: Value(_limit),
                  isShared: Value(_shared),
                ));
            if (context.mounted) Navigator.of(context).pop();
          },
        ),
        if (widget.existing != null)
          PrimaryAction(
            label: 'Hapus budget',
            destructive: true,
            onPressed: () async {
              final ok = await confirmDelete(context, title: 'Hapus budget ini?', message: 'Transaksinya tidak ikut terhapus.');
              if (!ok) return;
              await ref.read(dbProvider).softDeleteBudget(widget.existing!.id);
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        if (cats.isEmpty) Text('Belum ada kategori pengeluaran.', style: AuraType.bodySm.copyWith(color: p.error)),
      ],
    );
  }
}
