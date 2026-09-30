import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/icons/category_icons.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/lottie.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';
import '../../core/utils/rupiah.dart';
import '../../services/realtime.dart';
import 'goal_card.dart';

class GoalsPage extends ConsumerWidget {
  const GoalsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final goals = ref.watch(goalsProvider).value;
    final hidden = ref.watch(hideBalanceProvider);
    final totalSaved = (goals ?? const []).fold<int>(0, (s, g) => s + g.$2);
    final top = MediaQuery.paddingOf(context).top;

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
                  Text('Target Tabungan', style: AuraType.headlineLg.copyWith(color: p.onSurface)),
                  Row(
                    children: [
                      Text('Terkumpul ', style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)),
                      MoneyText(totalSaved, hidden: hidden, style: AuraType.labelLg.copyWith(color: p.primary)),
                    ],
                  ),
                ],
              ),
            ),
            NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Target baru', color: p.primary, onTap: () => showGoalForm(context)),
          ],
        ).staggerIn(0),
        const SizedBox(height: AuraSpace.lg),
        if (goals == null)
          const AuraLoadingView(label: 'Memuat target…')
        else if (goals.isEmpty)
          ClayEmpty(
            kind: ClayKind.travel,
            size: 180,
            title: 'Wujudkan impian pertama',
            message: 'Beri nama, tentukan nominal, lalu sisihkan sedikit demi sedikit. Kami hitung perkiraan kapan tercapainya.',
            action: ShadButton(onPressed: () => showGoalForm(context), child: const Text('Buat target')),
          ).staggerIn(1)
        else if (ref.watch(householdIdProvider) == null)
          for (final (i, (g, saved)) in goals.indexed)
            Padding(padding: const EdgeInsets.only(bottom: AuraSpace.md), child: GoalCard(goal: g, saved: saved).staggerIn(i + 1))
        else
          for (final (title, list) in [
            ('Bersama', goals.where((g) => g.$1.isShared).toList()),
            ('Pribadi', goals.where((g) => !g.$1.isShared).toList()),
          ])
            if (list.isNotEmpty) ...[
              SectionHeader(title == 'Bersama' ? 'Target bersama' : 'Target pribadiku'),
              const SizedBox(height: AuraSpace.sm + 4),
              for (final (i, (g, saved)) in list.indexed)
                Padding(padding: const EdgeInsets.only(bottom: AuraSpace.md), child: GoalCard(goal: g, saved: saved).staggerIn(i + 1)),
              const SizedBox(height: AuraSpace.sm),
            ],
      ],
    );
  }
}

Future<void> showGoalForm(BuildContext context, {Goal? existing}) {
  return showFormSheet<void>(context, title: existing == null ? 'Target baru' : 'Ubah target', builder: (_) => _GoalForm(existing: existing));
}

const _illustrationLabels = {
  'travel': 'Liburan',
  'shield': 'Dana darurat',
  'house': 'Rumah',
  'gadget': 'Gadget',
  'study': 'Pendidikan',
  'gift': 'Hadiah',
  'jar': 'Lainnya',
};

class _GoalForm extends ConsumerStatefulWidget {
  const _GoalForm({this.existing});
  final Goal? existing;

  @override
  ConsumerState<_GoalForm> createState() => _GoalFormState();
}

class _GoalFormState extends ConsumerState<_GoalForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _target = widget.existing?.target ?? 0;
  late String _art = widget.existing?.illustration ?? 'travel';
  late int _color = widget.existing?.color ?? categoryTones.first;
  late DateTime? _deadline = widget.existing?.deadline;
  late bool _shared = widget.existing?.isShared ?? true;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _target <= 0) {
      AuraToast.error(context, 'Isi nama dan nominal target');
      return;
    }
    final e = widget.existing;
    final owner = ownerStamp(ref);
    await ref.read(dbProvider).upsertGoal(GoalsCompanion(
          id: Value(e?.id ?? newId()),
          householdId: Value(e?.householdId ?? owner.householdId),
          createdBy: Value(e?.createdBy ?? owner.userId),
          createdAt: Value(e?.createdAt ?? DateTime.now()),
          name: Value(_name.text.trim()),
          target: Value(_target),
          illustration: Value(_art),
          color: Value(_color),
          deadline: Value(_deadline),
          achievedAt: Value(e?.achievedAt),
          archived: Value(e?.archived ?? false),
          isShared: Value(_shared),
        ));
    // Target bersama baru dikabarkan supaya pasangan bisa ikut menabung.
    if (e == null && _shared && ref.read(householdIdProvider) != null) {
      final name = ref.read(displayNameProvider).trim().split(' ').first;
      ref.read(realtimeProvider.notifier).notify(
            kind: 'goal',
            title: '${name.isEmpty ? 'Pasanganmu' : name} membuat target bersama: ${_name.text.trim()}',
            body: 'Target ${Rupiah.format(_target)}${_deadline == null ? '' : ' sebelum ${DateId.month(_deadline!)}'}. Yuk ikut menabung!',
          );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 120,
          child: ListView(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            children: [
              for (final entry in _illustrationLabels.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: NeuPressable(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _art = entry.key);
                    },
                    restDepth: _art == entry.key ? -0.9 : 0.8,
                    pressedDepth: -0.9,
                    radius: AuraRadius.lg,
                    width: 92,
                    color: _art == entry.key ? p.surfaceContainer : p.surfaceLow,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedScale(
                          scale: _art == entry.key ? 1.08 : 0.92,
                          duration: const Duration(milliseconds: 320),
                          curve: Curves.easeOutBack,
                          child: ClayArt(ClayArt.goalKinds[entry.key]!, size: 70, animate: _art == entry.key),
                        ),
                        Text(
                          entry.value,
                          style: AuraType.labelSm.copyWith(color: _art == entry.key ? p.primary : p.onSurfaceVariant, letterSpacing: 0),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const FieldLabel('Nama target'),
        ShadInput(controller: _name, placeholder: const Text('mis. Liburan ke Kyoto'), textCapitalization: TextCapitalization.sentences),
        const FieldLabel('Nominal target'),
        AmountField(initial: _target, onChanged: (v) => _target = v),
        const FieldLabel('Tenggat (opsional)'),
        NeuPressable(
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: _deadline ?? DateTime.now().add(const Duration(days: 180)),
              firstDate: DateTime.now(),
              lastDate: DateTime.now().add(const Duration(days: 365 * 30)),
            );
            if (d != null) setState(() => _deadline = d);
          },
          radius: AuraRadius.md,
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              AuraIcon(HugeIcons.strokeRoundedCalendar03, size: 18, color: p.primary),
              const SizedBox(width: 8),
              Text(_deadline == null ? 'Pilih tanggal' : DateId.short(_deadline!), style: AuraType.labelLg.copyWith(color: p.onSurface)),
              const Spacer(),
              if (_deadline != null)
                GestureDetector(onTap: () => setState(() => _deadline = null), child: AuraIcon(HugeIcons.strokeRoundedCancel01, size: 18)),
            ],
          ),
        ),
        const FieldLabel('Warna'),
        ToneSwatches(value: _color, onChanged: (c) => setState(() => _color = c)),
        if (ref.watch(householdIdProvider) != null)
          ShareToggle(
            title: 'Target bersama',
            value: _shared,
            locked: widget.existing?.isShared == true,
            sharedHint: 'Kamu & pasangan bisa melihat dan menyetor',
            privateHint: 'Tabungan pribadimu — pasangan tidak melihatnya',
            onChanged: (v) => setState(() => _shared = v),
          ),
        PrimaryAction(label: 'Simpan target', onPressed: _save),
      ],
    );
  }
}
