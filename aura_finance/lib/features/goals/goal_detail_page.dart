import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:lottie/lottie.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/illustrations/avatars.dart';
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
import '../../data/remote/neon.dart';
import '../../domain/finance_math.dart';
import '../../services/realtime.dart';
import 'goals_page.dart';

final _contributionsProvider = StreamProvider.family<List<GoalContribution>, String>(
  (ref, id) => ref.watch(dbProvider).watchContributions(id),
);

class GoalDetailPage extends ConsumerWidget {
  const GoalDetailPage({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final entry = (ref.watch(goalsProvider).value ?? const []).where((g) => g.$1.id == id).firstOrNull;
    if (entry == null) return const Scaffold(body: Center(child: AuraLoader()));
    final (goal, saved) = entry;
    final history = ref.watch(_contributionsProvider(id)).value ?? const [];
    final hidden = ref.watch(hideBalanceProvider);
    final inHousehold = ref.watch(householdIdProvider) != null;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final memberById = {for (final m in members) m.userId: m};
    final wallets = ref.watch(walletMapProvider);
    final ratio = goal.target <= 0 ? 0.0 : saved / goal.target;
    final eta = estimateGoalDate(target: goal.target, saved: saved, history: history);
    final remaining = math.max(0, goal.target - saved);
    int? perMonth;
    if (goal.deadline != null && remaining > 0) {
      final months = math.max(1, (goal.deadline!.difference(DateTime.now()).inDays / 30).ceil());
      perMonth = (remaining / months).ceil();
    }

    return AuraPage(
      title: goal.name,
      subtitle: ratio >= 1 ? 'Target tercapai' : '${(ratio * 100).toStringAsFixed(0)}% terkumpul',
      actions: [
        NeuIconButton(
          HugeIcons.strokeRoundedPencilEdit02,
          label: 'Ubah',
          onTap: () => showGoalForm(context, existing: goal),
        ),
        NeuIconButton(
          HugeIcons.strokeRoundedDelete02,
          label: 'Hapus',
          onTap: () async {
            final ok = await confirmDelete(context, title: 'Hapus target?', message: 'Target dan riwayat setorannya akan dihapus.');
            if (!ok) return;
            await ref.read(dbProvider).softDeleteGoal(goal.id);
            if (context.mounted) context.pop();
          },
        ),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverList.list(
            children: [
              const SizedBox(height: AuraSpace.md),
              Center(
                child: _GoalRing(
                  ratio: ratio,
                  color: Color(goal.color),
                  child: ClayArt(ratio >= 1 ? ClayKind.trophy : (ClayArt.goalKinds[goal.illustration] ?? ClayKind.jar), size: 150),
                ),
              ).staggerIn(0),
              if (inHousehold) ...[
                const SizedBox(height: AuraSpace.md),
                Center(
                  child: ShareBadge(
                    shared: goal.isShared,
                    avatars: [
                      for (final m in members.take(3))
                        AuraAvatar(avatarKey: m.avatar, name: m.displayName, fallbackColor: Color(m.color), size: 18, ring: p.primaryFixed),
                    ],
                  ),
                ).staggerIn(0),
              ],
              const SizedBox(height: AuraSpace.lg),
              Center(
                child: MoneyText(
                  saved,
                  hidden: hidden,
                  style: AuraType.currency.copyWith(color: p.onSurface),
                ),
              ).staggerIn(1),
              Center(
                child: Text(
                  hidden ? 'dari Rp •••' : 'dari ${Rupiah.format(goal.target)}',
                  style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
                ),
              ).staggerIn(1),
              const SizedBox(height: AuraSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: _Stat(label: 'Sisa', value: hidden ? 'Rp •••' : Rupiah.compact(remaining)),
                  ),
                  const SizedBox(width: AuraSpace.md),
                  Expanded(
                    child: _Stat(
                      label: perMonth != null ? 'Per bulan' : 'Perkiraan',
                      value: perMonth != null
                          ? (hidden ? 'Rp •••' : Rupiah.compact(perMonth))
                          : ratio >= 1
                          ? 'Selesai'
                          : eta == null
                          ? '—'
                          : DateId.month(eta),
                    ),
                  ),
                ],
              ).staggerIn(2),
              const SizedBox(height: AuraSpace.lg),
              Row(
                children: [
                  Expanded(
                    child: ShadButton.outline(
                      onPressed: saved > 0 ? () => _contribute(context, ref, goal, saved, withdraw: true) : null,
                      leading: const AuraIcon(HugeIcons.strokeRoundedArrowUp01, size: 18),
                      child: const Text('Tarik'),
                    ),
                  ),
                  const SizedBox(width: AuraSpace.md),
                  Expanded(
                    flex: 2,
                    child: ShadButton(
                      onPressed: () => _contribute(context, ref, goal, saved),
                      gradient: LinearGradient(colors: [p.primaryContainer, p.secondaryContainer]),
                      leading: const AuraIcon(HugeIcons.strokeRoundedArrowDown01, size: 18, color: Colors.white),
                      child: const Text('Setor', style: TextStyle(color: Colors.white)),
                    ),
                  ),
                ],
              ).staggerIn(3),
              if (inHousehold && goal.isShared && history.isNotEmpty) ...[
                const SizedBox(height: AuraSpace.xl),
                const SectionHeader('Kontribusi').staggerIn(4),
                const SizedBox(height: AuraSpace.sm + 4),
                _ContributionSplit(history: history, members: memberById, hidden: hidden).staggerIn(4),
              ],
              const SizedBox(height: AuraSpace.xl),
              const SectionHeader('Riwayat setoran').staggerIn(4),
              const SizedBox(height: AuraSpace.sm + 4),
              if (history.isEmpty)
                Text('Belum ada setoran.', style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)).staggerIn(5)
              else
                for (final (i, c) in history.indexed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _SwipeToDelete(
                      key: ValueKey('contrib-${c.id}'),
                      onDelete: () => _deleteContribution(context, ref, c),
                      child: NeuSurface(
                        radius: AuraRadius.md,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        child: Row(
                          children: [
                            if (inHousehold) ...[
                              AuraAvatar(
                                avatarKey: memberById[c.createdBy]?.avatar,
                                name: memberById[c.createdBy]?.displayName ?? '',
                                fallbackColor: Color(memberById[c.createdBy]?.color ?? 0xFFFE64A3),
                                size: 38,
                              ),
                              const SizedBox(width: 12),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _historyTitle(c, inHousehold ? memberById[c.createdBy] : null),
                                    style: AuraType.labelLg.copyWith(color: p.onSurface),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    [
                                      DateId.short(c.occurredAt),
                                      if (c.note.isNotEmpty) c.note,
                                      if (c.walletId != null)
                                        '${c.amount >= 0 ? 'dari' : 'ke'} ${wallets[c.walletId]?.wallet.name ?? 'dompet lain'}',
                                    ].join(' · '),
                                    style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              hidden ? 'Rp •••' : Rupiah.format(c.amount, signed: true),
                              style: AuraType.labelLg.copyWith(color: c.amount >= 0 ? p.tertiary : p.secondary),
                            ),
                          ],
                        ),
                      ),
                    ).staggerIn(5 + i, stepMs: 30),
                  ),
              if (history.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Geser setoran ke kiri untuk menghapus.', style: AuraType.bodySm.copyWith(color: p.outline)),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _deleteContribution(BuildContext context, WidgetRef ref, GoalContribution c) async {
    final db = ref.read(dbProvider);
    await db.softDeleteContribution(c.id);
    AuraToast.global(
      title: c.amount >= 0 ? 'Setoran dihapus' : 'Penarikan dihapus',
      message: c.walletId == null ? null : 'Saldo dompet ikut disesuaikan.',
      tone: AuraTone.warning,
      actionLabel: 'Urungkan',
      onAction: () => db.restoreContribution(c.id),
      duration: const Duration(seconds: 5),
    );
  }

  Future<void> _contribute(BuildContext context, WidgetRef ref, Goal goal, int saved, {bool withdraw = false}) async {
    final result = await showFormSheet<({int amount, String note, String? walletId})>(
      context,
      title: withdraw ? 'Tarik dari target' : 'Setor ke target',
      builder: (context) => _ContributeForm(goal: goal, saved: saved, withdraw: withdraw),
    );
    if (result == null) return;
    final amount = result.amount;
    final owner = ownerStamp(ref);
    final db = ref.read(dbProvider);
    await db.addContribution(
      GoalContributionsCompanion.insert(
        id: newId(),
        goalId: goal.id,
        amount: withdraw ? -amount : amount,
        occurredAt: DateTime.now(),
        note: Value(result.note),
        walletId: Value(result.walletId),
        householdId: Value(goal.householdId ?? owner.householdId),
        createdBy: Value(owner.userId),
      ),
    );
    final newSaved = saved + (withdraw ? -amount : amount);
    final reached = newSaved >= goal.target && saved < goal.target;
    await db.upsertGoal(
      goal.toCompanion(true).copyWith(achievedAt: Value(newSaved >= goal.target ? (goal.achievedAt ?? DateTime.now()) : null)),
    );

    // Kabari anggota lain untuk setiap setoran/penarikan di target bersama.
    if (goal.isShared && ref.read(householdIdProvider) != null) {
      final name = ref.read(displayNameProvider).trim().split(' ').first;
      final who = name.isEmpty ? 'Pasanganmu' : name;
      final pct = goal.target <= 0 ? 0 : (newSaved / goal.target * 100).clamp(0, 999).round();
      ref
          .read(realtimeProvider.notifier)
          .notify(
            kind: 'goal',
            title: reached
                ? 'Target ${goal.name} tercapai!'
                : withdraw
                ? '$who menarik ${Rupiah.format(amount)} dari ${goal.name}'
                : '$who menabung ${Rupiah.format(amount)} untuk ${goal.name}',
            body: reached
                ? '${Rupiah.format(goal.target)} sudah terkumpul penuh. Kerja bagus!'
                : 'Terkumpul ${Rupiah.format(newSaved)} dari ${Rupiah.format(goal.target)} ($pct%)',
          );
    }
    if (reached && context.mounted) {
      HapticFeedback.heavyImpact();
      await showCelebration(context, goal.name);
    } else {
      HapticFeedback.mediumImpact();
    }
  }
}

String _historyTitle(GoalContribution c, Member? by) {
  final who = by?.userId == Neon.auth.currentUser?.id ? 'Kamu' : by?.displayName.split(' ').first;
  if (who == null) return c.amount >= 0 ? 'Setoran' : 'Penarikan';
  return c.amount >= 0 ? '$who menyetor' : '$who menarik';
}

/// Formulir setor/tarik dengan pilihan dompet sumber (atau tujuan penarikan).
class _ContributeForm extends ConsumerStatefulWidget {
  const _ContributeForm({required this.goal, required this.saved, required this.withdraw});
  final Goal goal;
  final int saved;
  final bool withdraw;

  @override
  ConsumerState<_ContributeForm> createState() => _ContributeFormState();
}

class _ContributeFormState extends ConsumerState<_ContributeForm> {
  var _amount = 0;
  String? _walletId;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final inHousehold = ref.watch(householdIdProvider) != null;
    // Target pribadi hanya boleh memakai dompet pribadi, supaya saldo dompet bersama
    // di HP pasangan tidak berubah tanpa alasan yang bisa ia lihat.
    final wallets = (ref.watch(walletBalancesProvider).value ?? const <WalletBalance>[])
        .where((w) => !inHousehold || widget.goal.isShared || isMyPrivateWallet(w.wallet))
        .toList();
    final chosen = wallets.where((w) => w.wallet.id == _walletId).firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const FieldLabel('Nominal'),
        AmountField(initial: 0, onChanged: (v) => _amount = v),
        FieldLabel(widget.withdraw ? 'Kembalikan ke dompet' : 'Ambil dari dompet'),
        ShadSelect<String>(
          initialValue: '',
          onChanged: (v) => setState(() => _walletId = (v == null || v.isEmpty) ? null : v),
          options: [
            ShadOption(value: '', child: Text(widget.withdraw ? 'Tidak ke dompet' : 'Tidak dari dompet (catat saja)')),
            for (final w in wallets)
              ShadOption(
                value: w.wallet.id,
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(color: Color(w.wallet.color), shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(w.wallet.name)),
                    Text(Rupiah.compact(w.balance), style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
              ),
          ],
          selectedOptionBuilder: (context, v) =>
              Text(v.isEmpty ? (widget.withdraw ? 'Tidak ke dompet' : 'Tidak dari dompet (catat saja)') : (chosen?.wallet.name ?? '')),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            _walletId == null
                ? 'Saldo dompet tidak berubah — cocok untuk tabungan yang disimpan terpisah.'
                : widget.withdraw
                ? 'Saldo ${chosen?.wallet.name} bertambah sebesar nominal ini.'
                : 'Saldo ${chosen?.wallet.name} berkurang sebesar nominal ini.',
            style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
          ),
        ),
        const FieldLabel('Catatan (opsional)'),
        ShadInput(controller: _note, placeholder: const Text('mis. Sisa gaji Mei')),
        PrimaryAction(
          label: widget.withdraw ? 'Tarik' : 'Setor',
          onPressed: () {
            if (_amount <= 0) return AuraToast.error(context, 'Masukkan nominal');
            if (widget.withdraw && _amount > widget.saved) return AuraToast.error(context, 'Melebihi saldo target');
            if (!widget.withdraw && chosen != null && _amount > chosen.balance) {
              return AuraToast.error(
                context,
                'Saldo ${chosen.wallet.name} tidak cukup',
                message: 'Tersedia ${Rupiah.format(chosen.balance)}',
              );
            }
            Navigator.of(context).pop((amount: _amount, note: _note.text.trim(), walletId: _walletId));
          },
        ),
      ],
    );
  }
}

/// Bagan kontribusi per anggota: batang bertumpuk + rincian dengan avatar.
class _ContributionSplit extends StatelessWidget {
  const _ContributionSplit({required this.history, required this.members, required this.hidden});
  final List<GoalContribution> history;
  final Map<String, Member> members;
  final bool hidden;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final byUser = <String?, int>{};
    for (final c in history) {
      byUser[c.createdBy] = (byUser[c.createdBy] ?? 0) + c.amount;
    }
    final rows = byUser.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    final total = rows.fold<int>(0, (s, e) => s + e.value);
    if (total <= 0) return const SizedBox.shrink();
    Color toneOf(String? id) => Color(members[id]?.color ?? p.outline.toARGB32());

    return NeuSurface(
      radius: AuraRadius.lg,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AuraRadius.pill),
            child: SizedBox(
              height: 14,
              child: Row(
                children: [
                  for (final (i, e) in rows.indexed)
                    Expanded(
                      flex: math.max(1, (e.value / total * 1000).round()),
                      child: TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: 1),
                        duration: Duration(milliseconds: 700 + i * 150),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: v,
                            child: Container(
                              margin: EdgeInsets.only(right: i == rows.length - 1 ? 0 : 2),
                              color: toneOf(e.key),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          for (final e in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  AuraAvatar(
                    avatarKey: members[e.key]?.avatar,
                    name: members[e.key]?.displayName ?? '',
                    fallbackColor: toneOf(e.key),
                    size: 32,
                    ring: toneOf(e.key),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      e.key == Neon.auth.currentUser?.id ? 'Kamu' : (members[e.key]?.displayName ?? 'Anggota lama'),
                      style: AuraType.labelLg.copyWith(color: p.onSurface),
                    ),
                  ),
                  Text(hidden ? 'Rp •••' : Rupiah.compact(e.value), style: AuraType.labelLg.copyWith(color: p.onSurface)),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 44,
                    child: Text(
                      '${(e.value / total * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: AuraType.labelMd.copyWith(color: toneOf(e.key)),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuSurface(
      depth: -1,
      radius: AuraRadius.md,
      color: p.surfaceContainer,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 2),
          Text(
            value,
            style: AuraType.headlineSm.copyWith(color: p.onSurface),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Cincin progres: trek cekung + busur bergradien yang terisi dengan pegas.
class _GoalRing extends StatelessWidget {
  const _GoalRing({required this.ratio, required this.color, required this.child});
  final double ratio;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuSurface(
      circle: true,
      width: 250,
      height: 250,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: ratio.clamp(0, 1)),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeOutCubic,
        builder: (context, v, child) => CustomPaint(painter: _RingPainter(v, color, p), child: child),
        child: Center(child: child),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.v, this.color, this.p);
  final double v;
  final Color color;
  final AuraPalette p;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 18;
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..color = p.surfaceHigh,
    );
    if (v <= 0) return;
    final rect = Rect.fromCircle(center: c, radius: r);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: -math.pi / 2,
          endAngle: math.pi * 1.5,
          colors: [p.secondaryContainer, color, color],
          stops: const [0, 0.6, 1],
          transform: const GradientRotation(-math.pi / 2),
        ).createShader(rect),
    );
    final end = -math.pi / 2 + math.pi * 2 * v;
    canvas.drawCircle(Offset(c.dx + r * math.cos(end), c.dy + r * math.sin(end)), 5, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.color != color || o.p != p;
}

/// Perayaan target tercapai: piala clay + konfeti yang jatuh.
Future<void> showCelebration(BuildContext context, String name) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Tutup',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 520),
    transitionBuilder: (c, a, _, child) => ScaleTransition(
      scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
      child: FadeTransition(opacity: a, child: child),
    ),
    pageBuilder: (context, _, _) {
      final p = context.aura;
      return Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _Confetti())),
          // Letupan konfeti Lottie dari bawah, di atas hujan konfeti.
          Positioned.fill(
            child: IgnorePointer(
              child: Lottie.asset(AuraLottie.confetti, repeat: false, fit: BoxFit.cover, alignment: Alignment.bottomCenter),
            ),
          ),
          Center(
            child: Material(
              color: Colors.transparent,
              child: NeuSurface(
                radius: AuraRadius.xl,
                width: 300,
                padding: const EdgeInsets.all(AuraSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const ClayArt(ClayKind.trophy, size: 170),
                    Text('Target tercapai!', style: AuraType.headlineMd.copyWith(color: p.onSurface)),
                    const SizedBox(height: 4),
                    Text(
                      '“$name” sudah terkumpul penuh. Kerja bagus.',
                      textAlign: TextAlign.center,
                      style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
                    ),
                    const SizedBox(height: AuraSpace.md),
                    ShadButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Mantap')),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _Confetti extends StatefulWidget {
  const _Confetti();

  @override
  State<_Confetti> createState() => _ConfettiState();
}

class _ConfettiState extends State<_Confetti> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600))..forward();
  final _rnd = math.Random();
  late final _pieces = List.generate(
    46,
    (_) => (
      x: _rnd.nextDouble(),
      delay: _rnd.nextDouble() * 0.35,
      speed: 0.7 + _rnd.nextDouble() * 0.6,
      size: 6 + _rnd.nextDouble() * 8,
      spin: _rnd.nextDouble() * 6,
      tone: _rnd.nextInt(4),
      round: _rnd.nextBool(),
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final tones = [p.primaryContainer, p.secondaryContainer, p.tertiaryContainer, const Color(0xFFF2C46B)];
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => CustomPaint(painter: _ConfettiPainter(_c.value, _pieces, tones)),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.t, this.pieces, this.tones);
  final double t;
  final List<({double x, double delay, double speed, double size, double spin, int tone, bool round})> pieces;
  final List<Color> tones;

  @override
  void paint(Canvas canvas, Size size) {
    for (final pc in pieces) {
      final local = ((t - pc.delay) / (1 - pc.delay)).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final y = -20 + (size.height + 40) * Curves.easeIn.transform(local) * pc.speed;
      final x = pc.x * size.width + math.sin(local * 8 + pc.spin) * 18;
      final paint = Paint()..color = tones[pc.tone].withValues(alpha: 1 - local * 0.6);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(local * pc.spin * 4);
      if (pc.round) {
        canvas.drawCircle(Offset.zero, pc.size / 2, paint);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: pc.size, height: pc.size * 0.5), const Radius.circular(2)),
          paint,
        );
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter o) => o.t != t;
}

/// Geser ke kiri untuk menghapus (sama seperti baris transaksi).
class _SwipeToDelete extends StatelessWidget {
  const _SwipeToDelete({super.key, required this.child, required this.onDelete});
  final Widget child;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Dismissible(
      key: key!,
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
      onDismissed: (_) => onDelete(),
      child: child,
    );
  }
}
