import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:local_auth/local_auth.dart';

import '../core/illustrations/clay.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/neu_surface.dart';
import '../core/widgets/primitives.dart';

import '../data/providers.dart';

class AppLockEnabled extends Notifier<bool> {
  static const _key = 'app_lock';
  @override
  bool build() => ref.read(prefsProvider).getBool(_key) ?? false;

  /// Mengaktifkan hanya jika perangkat mendukung & pengguna berhasil verifikasi.
  Future<bool> set(bool value) async {
    if (value) {
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) return false;
      final ok = await auth.authenticate(localizedReason: 'Aktifkan kunci aplikasi Aura');
      if (!ok) return false;
    }
    state = value;
    await ref.read(prefsProvider).setBool(_key, value);
    return true;
  }
}

final appLockEnabledProvider = NotifierProvider<AppLockEnabled, bool>(AppLockEnabled.new);

/// Menutup aplikasi dengan layar kunci saat dibuka / kembali dari latar belakang > 1 menit.
class AppLockGate extends ConsumerStatefulWidget {
  const AppLockGate({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = ref.read(appLockEnabledProvider);
  DateTime? _pausedAt;
  bool _authenticating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!ref.read(appLockEnabledProvider) || _authenticating) return;
    if (state == AppLifecycleState.paused) _pausedAt = DateTime.now();
    if (state == AppLifecycleState.resumed && _pausedAt != null && DateTime.now().difference(_pausedAt!) > const Duration(minutes: 1)) {
      setState(() => _locked = true);
      _unlock();
    }
  }

  Future<void> _unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await LocalAuthentication().authenticate(localizedReason: 'Buka Aura', persistAcrossBackgrounding: true);
      if (ok && mounted) setState(() => _locked = false);
    } catch (_) {
      // Tetap terkunci; pengguna bisa mencoba lagi.
    } finally {
      _authenticating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) Positioned.fill(child: _LockScreen(onUnlock: _unlock)),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  const _LockScreen({required this.onUnlock});
  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Material(
      color: p.surface,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const ClayArt(ClayKind.shield, size: 180),
            const SizedBox(height: AuraSpace.md),
            Text('Aura terkunci', style: AuraType.headlineMd.copyWith(color: p.onSurface)),
            const SizedBox(height: 4),
            Text('Verifikasi untuk melihat keuanganmu', style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)),
            const Spacer(),
            NeuPressable(
              onTap: onUnlock,
              circle: true,
              width: 76,
              height: 76,
              semanticLabel: 'Buka kunci',
              child: Center(child: AuraIcon(HugeIcons.strokeRoundedFingerPrint, size: 34, color: p.primary)),
            ),
            const SizedBox(height: AuraSpace.xl + 16),
          ],
        ),
      ),
    );
  }
}
