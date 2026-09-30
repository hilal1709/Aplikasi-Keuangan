import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/primitives.dart';
import '../../data/providers.dart';

/// Pilihan cakupan Semua / Bersama / Pribadiku untuk Beranda & Insight.
/// Hanya tampil saat pengguna tergabung dalam rumah tangga.
class ScopeSwitch extends ConsumerWidget {
  const ScopeSwitch({super.key, this.showHint = true});
  final bool showHint;

  static const labels = {ViewScope.all: 'Semua', ViewScope.shared: 'Bersama', ViewScope.mine: 'Pribadiku'};

  static const hints = {
    ViewScope.all: 'Semua dompet yang bisa kamu lihat',
    ViewScope.shared: 'Hanya dompet bersama rumah tangga',
    ViewScope.mine: 'Hanya dompet pribadimu — tidak terlihat pasangan',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(householdIdProvider) == null) return const SizedBox.shrink();
    final p = context.aura;
    final scope = ref.watch(viewScopeProvider);
    return Padding(
      padding: const EdgeInsets.only(bottom: AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NeuSegmented<ViewScope>(
            value: scope,
            options: labels,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              ref.read(viewScopeProvider.notifier).set(v);
            },
          ),
          if (showHint) ...[
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                hints[scope]!,
                key: ValueKey(scope),
                textAlign: TextAlign.center,
                style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
