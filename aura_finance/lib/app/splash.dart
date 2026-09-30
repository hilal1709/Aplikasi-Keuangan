import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/lottie.dart';
import '../core/widgets/primitives.dart';

/// Menampilkan [splash] selama [init] berjalan (minimal [minDuration]),
/// lalu berpindah ke aplikasi dengan fade + zoom halus.
class BootGate extends StatefulWidget {
  const BootGate({super.key, required this.init, required this.builder, this.minDuration = const Duration(milliseconds: 1200)});
  final Future<Object?> Function() init;
  final Widget Function(Object? result) builder;
  final Duration minDuration;

  @override
  State<BootGate> createState() => _BootGateState();
}

class _BootGateState extends State<BootGate> {
  Widget? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final minWait = Future<void>.delayed(widget.minDuration);
      final result = await widget.init();
      await minWait;
      if (mounted) setState(() => _app = widget.builder(result));
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 650),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: child is _SplashApp ? 1.08 : 0.97, end: 1.0).animate(anim), child: child),
        ),
        child: _app ?? _SplashApp(error: _error, onRetry: () {
          setState(() => _error = null);
          _boot();
        }),
      ),
    );
  }
}

class _SplashApp extends StatelessWidget {
  const _SplashApp({this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.material(AuraPalette.light),
      darkTheme: AppTheme.material(AuraPalette.dark),
      home: _Splash(error: error, onRetry: onRetry),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash({this.error, required this.onRetry});
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Scaffold(
      backgroundColor: p.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Logo(color: p.primary),
            const SizedBox(height: AuraSpace.md),
            Text('Aura', style: AuraType.headlineLg.copyWith(color: p.onSurface)).staggerIn(0, baseMs: 350),
            Text('Keuangan bersama, tanpa ribet', style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)).staggerIn(1, baseMs: 350, stepMs: 90),
            const SizedBox(height: AuraSpace.xl),
            SizedBox(
              height: 48,
              child: AnimatedSwitcher(
                duration: Motion.base,
                child: error == null
                    ? const AuraLoader(width: 64).staggerIn(2, baseMs: 350, stepMs: 150)
                    : TextButton(onPressed: onRetry, child: const Text('Gagal memuat — coba lagi')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Logo yang meletup masuk lalu "bernapas" pelan selama memuat.
class _Logo extends StatefulWidget {
  const _Logo({required this.color});
  final Color color;

  @override
  State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_enter.isAnimating || _enter.isCompleted) return;
    if (Motion.reduced(context)) {
      _enter.value = 1;
    } else {
      _enter.forward().then((_) {
        if (mounted) _breath.repeat(reverse: true);
      });
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _breath]),
      builder: (context, child) {
        final e = Curves.elasticOut.transform(_enter.value);
        final b = Curves.easeInOut.transform(_breath.value);
        return Opacity(
          opacity: (_enter.value * 3).clamp(0, 1),
          child: Transform.rotate(
            angle: (1 - e) * -0.5,
            child: Transform.scale(
              scale: (0.3 + 0.7 * e) * (1 + 0.04 * b),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: widget.color.withValues(alpha: 0.18 + 0.14 * b), blurRadius: 30 + 16 * b, spreadRadius: 2)],
                ),
                child: child,
              ),
            ),
          ),
        );
      },
      child: Image.asset('assets/brand/logo_mark.png', width: 96, height: 96),
    );
  }
}
