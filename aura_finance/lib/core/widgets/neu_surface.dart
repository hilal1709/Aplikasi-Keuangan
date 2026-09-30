import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'primitives.dart' show Motion;

/// Permukaan neumorph dengan kedalaman kontinu:
/// `1` = timbul (extruded), `0` = rata, `-1` = cekung (inset).
/// Karena kontinu, perpindahan timbul -> cekung bisa dianimasikan mulus.
class NeuSurface extends StatelessWidget {
  const NeuSurface({
    super.key,
    this.depth = 1,
    this.radius = AuraRadius.lg,
    this.color,
    this.padding,
    this.width,
    this.height,
    this.circle = false,
    this.intensity = 1,
    this.child,
  });

  final double depth;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool circle;
  final double intensity;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final up = depth.clamp(0.0, 1.0) * intensity;
    final down = (-depth).clamp(0.0, 1.0) * intensity;
    final borderRadius = BorderRadius.circular(circle ? AuraRadius.pill : radius);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color ?? p.surfaceLow,
        borderRadius: circle ? null : borderRadius,
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        boxShadow: up == 0
            ? null
            : [
                BoxShadow(color: p.shadowLight.withValues(alpha: p.shadowLight.a * up), offset: Offset(-6 * up, -6 * up), blurRadius: 14 * up),
                BoxShadow(color: p.shadowDark.withValues(alpha: p.shadowDark.a * up), offset: Offset(6 * up, 6 * up), blurRadius: 14 * up),
              ],
      ),
      child: CustomPaint(
        painter: down == 0 ? null : _InsetShadowPainter(p, down, circle ? AuraRadius.pill : radius),
        child: padding == null ? child : Padding(padding: padding!, child: child),
      ),
    );
  }
}

class _InsetShadowPainter extends CustomPainter {
  _InsetShadowPainter(this.p, this.amount, this.radius);
  final AuraPalette p;
  final double amount;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius.clamp(0, size.shortestSide / 2)));
    canvas.save();
    canvas.clipRRect(r);
    final d = 4 * amount;
    _shadow(canvas, r, Offset(d, d), p.shadowDark.withValues(alpha: p.shadowDark.a * 0.9 * amount));
    _shadow(canvas, r, Offset(-d, -d), p.shadowLight.withValues(alpha: p.shadowLight.a * amount));
    canvas.restore();
  }

  void _shadow(Canvas canvas, RRect r, Offset offset, Color color) {
    final outer = Path()..addRect(r.outerRect.inflate(40));
    final hole = Path()..addRRect(r.shift(offset));
    final ring = Path.combine(PathOperation.difference, outer, hole);
    canvas.drawPath(
      ring,
      Paint()
        ..color = color
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, 5 * amount),
    );
  }

  @override
  bool shouldRepaint(_InsetShadowPainter old) => old.amount != amount || old.p != p || old.radius != radius;
}

/// Elemen yang bisa ditekan: permukaan "tenggelam" dari timbul ke cekung,
/// sedikit mengecil, dan memberi getaran haptic ringan.
class NeuPressable extends StatefulWidget {
  const NeuPressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.radius = AuraRadius.lg,
    this.color,
    this.padding,
    this.width,
    this.height,
    this.circle = false,
    this.restDepth = 1,
    this.pressedDepth = -0.7,
    this.pressedScale = 0.96,
    this.haptic = true,
    this.semanticLabel,
    this.tilt = true,
    this.glow = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double radius;
  final Color? color;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final bool circle;
  final double restDepth;
  final double pressedDepth;
  final double pressedScale;
  final bool haptic;
  final String? semanticLabel;

  /// Miring 3D ke arah titik sentuh saat ditekan.
  final bool tilt;

  /// Cahaya lembut yang menyebar dari titik sentuh.
  final bool glow;

  @override
  State<NeuPressable> createState() => _NeuPressableState();
}

class _NeuPressableState extends State<NeuPressable> with TickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Curves.elasticOut);
  // Cahaya yang menyebar dari titik sentuh.
  late final AnimationController _glow = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  Offset _at = Offset.zero;
  Offset _tilt = Offset.zero;

  @override
  void dispose() {
    _c.dispose();
    _glow.dispose();
    super.dispose();
  }

  void _down(TapDownDetails d) {
    final size = context.size;
    if (size != null && !Motion.reduced(context)) {
      _at = d.localPosition;
      if (widget.tilt) {
        _tilt = Offset(
          ((d.localPosition.dx / size.width) * 2 - 1).clamp(-1.0, 1.0),
          ((d.localPosition.dy / size.height) * 2 - 1).clamp(-1.0, 1.0),
        );
      }
      if (widget.glow) _glow.forward(from: 0);
    }
    _c.forward();
  }

  void _up() => _c.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    final p = context.aura;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? _down : null,
        onTapUp: enabled ? (_) => _up() : null,
        onTapCancel: enabled ? _up : null,
        onTap: widget.onTap == null
            ? null
            : () {
                if (widget.haptic) HapticFeedback.lightImpact();
                widget.onTap!();
              },
        onLongPress: widget.onLongPress == null
            ? null
            : () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              },
        child: AnimatedBuilder(
          animation: Listenable.merge([_t, _glow]),
          builder: (context, child) {
            final t = _t.value.clamp(0.0, 1.0);
            final depth = ui.lerpDouble(widget.restDepth, widget.pressedDepth, t)!;
            final scale = ui.lerpDouble(1, widget.pressedScale, _t.value)!;
            // Miring ringan ke arah jari (perspektif 3D), kembali memantul saat dilepas.
            final tilt = Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateX(-_tilt.dy * 0.07 * _t.value)
              ..rotateY(_tilt.dx * 0.07 * _t.value)
              ..scaleByDouble(scale, scale, 1, 1);
            final glowing = _glow.isAnimating;
            return Transform(
              alignment: Alignment.center,
              transform: tilt,
              child: NeuSurface(
                depth: depth,
                radius: widget.radius,
                color: widget.color,
                width: widget.width,
                height: widget.height,
                circle: widget.circle,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    widget.padding == null ? child! : Padding(padding: widget.padding!, child: child),
                    if (glowing)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(widget.circle ? AuraRadius.pill : widget.radius),
                            child: CustomPaint(painter: _GlowPainter(_at, _glow.value, p.primaryContainer)),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.at, this.t, this.color);
  final Offset at;
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.longestSide * (0.25 + 1.1 * Curves.easeOutCubic.transform(t));
    final a = 0.28 * (1 - Curves.easeIn.transform(t));
    canvas.drawCircle(
      at,
      r,
      Paint()
        ..shader = RadialGradient(colors: [color.withValues(alpha: a), color.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: at, radius: r)),
    );
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.t != t || old.at != at || old.color != color;
}
