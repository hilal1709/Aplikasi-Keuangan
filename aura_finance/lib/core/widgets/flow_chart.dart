import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

class FlowBucket {
  const FlowBucket({required this.label, required this.caption, required this.income, required this.expense});
  final String label;
  final String caption;
  final int income;
  final int expense;
}

/// Grafik batang ganda (masuk/keluar) dengan:
/// - batang tumbuh bertahap saat data muncul (elastic, berjenjang),
/// - batang aktif naik & menebal, titik penanda memantul di atasnya,
/// - geser jari untuk berpindah batang (dengan klik haptic).
class FlowChart extends StatefulWidget {
  const FlowChart({super.key, required this.buckets, required this.selected, required this.onSelect, this.height = 150});
  final List<FlowBucket> buckets;
  final int selected;
  final ValueChanged<int> onSelect;
  final double height;

  @override
  State<FlowChart> createState() => _FlowChartState();
}

class _FlowChartState extends State<FlowChart> with TickerProviderStateMixin {
  late final AnimationController _grow = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..forward();
  late final AnimationController _focus = AnimationController(vsync: this, duration: const Duration(milliseconds: 420))..value = 1;
  late final AnimationController _bounce = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  int _prev = -1;

  @override
  void didUpdateWidget(FlowChart old) {
    super.didUpdateWidget(old);
    if (old.buckets.length != widget.buckets.length || old.buckets.first.label != widget.buckets.first.label) {
      _grow.forward(from: 0);
    }
    if (old.selected != widget.selected) {
      _prev = old.selected;
      _focus.forward(from: 0);
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _grow.dispose();
    _focus.dispose();
    _bounce.dispose();
    super.dispose();
  }

  void _hit(Offset local, double width) {
    final n = widget.buckets.length;
    final i = (local.dx / (width / n)).floor().clamp(0, n - 1);
    if (i != widget.selected) {
      HapticFeedback.selectionClick();
      widget.onSelect(i);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return LayoutBuilder(
      builder: (context, box) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) => _hit(d.localPosition, box.maxWidth),
        onHorizontalDragUpdate: (d) => _hit(d.localPosition, box.maxWidth),
        child: AnimatedBuilder(
          animation: Listenable.merge([_grow, _focus, _bounce]),
          builder: (context, _) => CustomPaint(
            size: Size(box.maxWidth, widget.height),
            painter: _FlowPainter(
              buckets: widget.buckets,
              selected: widget.selected,
              previous: _prev,
              grow: _grow.value,
              focus: Curves.easeOutBack.transform(_focus.value),
              bounce: math.sin(Curves.easeOut.transform(_bounce.value) * math.pi),
              p: p,
              labelStyle: DefaultTextStyle.of(context).style,
            ),
          ),
        ),
      ),
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.buckets,
    required this.selected,
    required this.previous,
    required this.grow,
    required this.focus,
    required this.bounce,
    required this.p,
    required this.labelStyle,
  });

  final List<FlowBucket> buckets;
  final int selected;
  final int previous;
  final double grow;
  final double focus;
  final double bounce;
  final AuraPalette p;
  final TextStyle labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 22.0;
    const topPad = 18.0;
    final chartH = size.height - labelH - topPad;
    final baseY = topPad + chartH;
    final maxV = buckets.fold<int>(1, (m, b) => math.max(m, math.max(b.income, b.expense)));
    final n = buckets.length;
    final slot = size.width / n;

    // Garis bantu putus-putus.
    final guide = Paint()
      ..color = p.outlineVariant.withValues(alpha: 0.5)
      ..strokeWidth = 1.2;
    for (final f in [0.0, 0.5]) {
      final y = topPad + chartH * f;
      for (var x = 0.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, size.width), y), guide);
      }
    }
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), guide..color = p.outlineVariant.withValues(alpha: 0.8));

    for (var i = 0; i < n; i++) {
      final b = buckets[i];
      // Pertumbuhan berjenjang: tiap batang mulai sedikit setelah batang sebelumnya.
      final start = (i / n) * 0.45;
      final g = Curves.elasticOut.transform(((grow - start) / 0.55).clamp(0.0, 1.0));
      final isSel = i == selected;
      final emphasis = isSel ? focus : (i == previous ? 1 - focus : 0.0);
      final barW = math.min(12.0, slot * 0.22) + 2 * emphasis;
      final cx = slot * i + slot / 2;

      void bar(double value, double x, Color rest, Color active) {
        final h = math.max(value == 0 ? 0.0 : 6.0, chartH * (value / maxV)) * g + 6 * emphasis * (value > 0 ? 1 : 0);
        if (h <= 0) return;
        final r = RRect.fromRectAndRadius(Rect.fromLTWH(x - barW / 2, baseY - h, barW, h), Radius.circular(barW / 2));
        final color = Color.lerp(rest, active, emphasis)!;
        if (emphasis > 0) {
          canvas.drawRRect(
            r.shift(const Offset(0, 4)),
            Paint()
              ..color = active.withValues(alpha: 0.3 * emphasis)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
          );
        }
        canvas.drawRRect(r, Paint()..color = color);
      }

      final gap = barW * 0.65;
      bar(b.income.toDouble(), cx - gap, p.isDark ? p.tertiaryFixed : const Color(0xFFC2CAA7), p.tertiary);
      bar(b.expense.toDouble(), cx + gap, p.secondaryContainer, p.primaryContainer);

      if (isSel && (b.income > 0 || b.expense > 0)) {
        final top = baseY - chartH * (math.max(b.income, b.expense) / maxV) * g - 14 - 6 * bounce;
        canvas.drawCircle(Offset(cx, top), 3.5 * focus, Paint()..color = p.primaryContainer);
      }

      final tp = TextPainter(
        text: TextSpan(
          text: b.label,
          style: labelStyle.merge(AuraType.labelSm).copyWith(
                color: isSel ? p.primary : p.outline,
                fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
                letterSpacing: 0,
              ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(cx - tp.width / 2, baseY + 6));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter o) =>
      o.grow != grow || o.focus != focus || o.bounce != bounce || o.selected != selected || o.buckets != buckets || o.p != p;
}
