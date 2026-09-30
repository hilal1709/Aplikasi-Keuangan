import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart';

/// Animasi Lottie Aura (dibuat oleh `tool/gen_lottie.py`, warnanya ditimpa sesuai tema).
abstract final class AuraLottie {
  static const loading = 'assets/lottie/loading.json';
  static const success = 'assets/lottie/success.json';
  static const error = 'assets/lottie/error.json';
}

/// Tiga titik yang melompat — indikator memuat standar aplikasi.
class AuraLoader extends StatelessWidget {
  const AuraLoader({super.key, this.width = 72, this.color, this.accent});
  final double width;
  final Color? color;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final main = color ?? p.primary;
    final alt = accent ?? p.primaryContainer;
    return Semantics(
      label: 'Memuat',
      child: Lottie.asset(
        AuraLottie.loading,
        width: width,
        height: width / 2,
        animate: !Motion.reduced(context),
        delegates: LottieDelegates(values: [
          ValueDelegate.color(const ['dot0', '**'], value: main),
          ValueDelegate.color(const ['dot1', '**'], value: alt),
          ValueDelegate.color(const ['dot2', '**'], value: main),
        ]),
      ),
    );
  }
}

/// Keadaan memuat sebuah halaman/daftar: loader + teks kecil, muncul dengan fade.
class AuraLoadingView extends StatelessWidget {
  const AuraLoadingView({super.key, this.label = 'Memuat…', this.height = 260});
  final String label;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AuraLoader(),
            const SizedBox(height: AuraSpace.sm),
            Text(label, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
          ],
        ),
      ),
    ).staggerIn(0, baseMs: 120);
  }
}

/// Lingkaran yang meletup + centang/silang yang tergambar, diputar sekali.
class AuraBurst extends StatelessWidget {
  const AuraBurst.success({super.key, this.size = 96, this.color}) : asset = AuraLottie.success;
  const AuraBurst.error({super.key, this.size = 96, this.color}) : asset = AuraLottie.error;
  final String asset;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final tone = color ?? (asset == AuraLottie.success ? p.tertiary : p.error);
    final reduced = Motion.reduced(context);
    return Lottie.asset(
      asset,
      width: size,
      height: size,
      repeat: false,
      animate: !reduced,
      // Saat animasi dimatikan, tampilkan bingkai terakhir (tanda sudah utuh).
      controller: reduced ? const AlwaysStoppedAnimation(1.0) : null,
      delegates: LottieDelegates(values: [ValueDelegate.color(const ['**'], value: tone)]),
    );
  }
}
