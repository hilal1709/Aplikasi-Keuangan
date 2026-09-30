import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/illustrations/avatars.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';

class GoalCard extends ConsumerWidget {
  const GoalCard({super.key, required this.goal, required this.saved});
  final Goal goal;
  final int saved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final hidden = ref.watch(hideBalanceProvider);
    final ratio = goal.target <= 0 ? 0.0 : saved / goal.target;
    final pct = (ratio * 100).clamp(0, 999);
    final done = ratio >= 1;
    final tone = Color(goal.color);
    final inHousehold = ref.watch(householdIdProvider) != null;
    final members = ref.watch(membersProvider).value ?? const <Member>[];

    return NeuPressable(
      onTap: () => context.push('/goal/${goal.id}'),
      radius: AuraRadius.xl,
      pressedScale: 0.985,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        children: [
          Row(
            children: [
              NeuSurface(
                depth: 0.8,
                radius: 18,
                width: 58,
                height: 58,
                color: p.surfaceContainer,
                child: Center(child: ClayArt(ClayArt.goalKinds[goal.illustration] ?? ClayKind.jar, size: 52, animate: false)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(goal.name, style: AuraType.headlineSm.copyWith(color: p.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (inHousehold)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: ShareBadge(
                          shared: goal.isShared,
                          avatars: [
                            for (final m in members.take(3))
                              AuraAvatar(avatarKey: m.avatar, name: m.displayName, fallbackColor: Color(m.color), size: 18, ring: p.primaryFixed),
                          ],
                        ),
                      ),
                    Text(
                      done
                          ? 'Tercapai'
                          : goal.deadline == null
                              ? 'Tanpa tenggat'
                              : 'Target: ${DateId.month(goal.deadline!)}',
                      style: AuraType.bodySm.copyWith(color: done ? p.tertiary : p.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: done ? p.tertiaryFixed : p.primaryFixed,
                  borderRadius: BorderRadius.circular(AuraRadius.pill),
                ),
                child: Text(
                  '${pct.toStringAsFixed(pct < 10 && pct > 0 ? 1 : 0)}%',
                  style: AuraType.labelSm.copyWith(color: done ? p.onTertiaryFixed : p.onPrimaryFixed),
                ),
              ).popIn(delayMs: 250),
            ],
          ),
          const SizedBox(height: AuraSpace.sm + 4),
          NeuProgress(
            value: ratio,
            colors: done ? [p.tertiary, p.tertiaryContainer] : [tone, Color.lerp(tone, p.secondaryContainer, 0.5)!],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              MoneyText(saved, hidden: hidden, style: AuraType.labelMd.copyWith(color: p.onSurface)),
              const Spacer(),
              Text(
                hidden ? 'dari Rp •••' : 'dari ${Rupiah.format(goal.target)}',
                style: AuraType.labelSm.copyWith(color: p.onSurfaceVariant, fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
