import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

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

  @override
  State<NeuPressable> createState() => _NeuPressableState();
}

class _NeuPressableState extends State<NeuPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
    reverseDuration: const Duration(milliseconds: 260),
  );
  late final Animation<double> _t = CurvedAnimation(parent: _c, curve: Curves.easeOut, reverseCurve: Curves.elasticOut);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _down() => _c.forward();
  void _up() => _c.reverse();

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null || widget.onLongPress != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => _down() : null,
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
          animation: _t,
          builder: (context, child) {
            final t = _t.value.clamp(0.0, 1.0);
            final depth = ui.lerpDouble(widget.restDepth, widget.pressedDepth, t)!;
            final scale = ui.lerpDouble(1, widget.pressedScale, _t.value)!;
            return Transform.scale(
              scale: scale,
              child: NeuSurface(
                depth: depth,
                radius: widget.radius,
                color: widget.color,
                padding: widget.padding,
                width: widget.width,
                height: widget.height,
                circle: widget.circle,
                child: child,
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}
