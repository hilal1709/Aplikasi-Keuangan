import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/lottie.dart';

/// Ilustrasi bergaya clay/3D lembut, digambar dengan kode.
/// Setiap ilustrasi punya gerak "idle" halus: melayang, dan bayangannya ikut mengecil.
enum ClayKind { jar, duo, wallet, chart, travel, shield, house, gadget, study, gift, trophy, calendar, search }

class ClayArt extends StatefulWidget {
  const ClayArt(this.kind, {super.key, this.size = 180, this.animate = true});
  final ClayKind kind;
  final double size;
  final bool animate;

  /// Kunci ilustrasi target tabungan yang bisa dipilih pengguna.
  static const goalKinds = {
    'travel': ClayKind.travel,
    'shield': ClayKind.shield,
    'house': ClayKind.house,
    'gadget': ClayKind.gadget,
    'study': ClayKind.study,
    'gift': ClayKind.gift,
    'jar': ClayKind.jar,
  };

  @override
  State<ClayArt> createState() => _ClayArtState();
}

class _ClayArtState extends State<ClayArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

  @override
  void initState() {
    super.initState();
    if (widget.animate) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) => CustomPaint(painter: _ClayPainter(widget.kind, p, _c.value)),
        ),
      ),
    );
  }
}

class _ClayPainter extends CustomPainter {
  _ClayPainter(this.kind, this.p, this.t);
  final ClayKind kind;
  final AuraPalette p;
  final double t;

  // Warna clay — bersumber dari palet referensi.
  Color get rose => const Color(0xFFFE7FB2);
  Color get berry => const Color(0xFFC0306F);
  Color get blush => const Color(0xFFFFB9B4);
  Color get sage => const Color(0xFFA7B08C);
  Color get moss => const Color(0xFF6E7856);
  Color get cream => const Color(0xFFFFF1EA);
  Color get apricot => const Color(0xFFF4B77E);
  Color get gold => const Color(0xFFF2C46B);

  double get bob => math.sin(t * math.pi * 2) * 4;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 200;
    canvas.scale(s);
    _groundShadow(canvas, const Offset(100, 176), 64 - bob, 12);
    canvas.save();
    canvas.translate(0, bob - 2);
    switch (kind) {
      case ClayKind.jar:
        _jar(canvas);
      case ClayKind.duo:
        _duo(canvas);
      case ClayKind.wallet:
        _wallet(canvas);
      case ClayKind.chart:
        _chart(canvas);
      case ClayKind.travel:
        _travel(canvas);
      case ClayKind.shield:
        _shield(canvas);
      case ClayKind.house:
        _house(canvas);
      case ClayKind.gadget:
        _gadget(canvas);
      case ClayKind.study:
        _study(canvas);
      case ClayKind.gift:
        _gift(canvas);
      case ClayKind.trophy:
        _trophy(canvas);
      case ClayKind.calendar:
        _calendar(canvas);
      case ClayKind.search:
        _search(canvas);
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Kit clay

  void _groundShadow(Canvas c, Offset center, double w, double h) {
    c.drawOval(
      Rect.fromCenter(center: center, width: w * 2, height: h * 2),
      Paint()
        ..color = p.shadowDark.withValues(alpha: p.isDark ? 0.5 : 0.35)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 10),
    );
  }

  Color _shade(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  /// Mengisi bentuk dengan gradien radial (terang kiri-atas, gelap kanan-bawah),
  /// bayangan dalam di tepi bawah, dan kilau spekular kecil.
  void clay(Canvas c, Path path, Color base, {bool gloss = true, double glossScale = 1}) {
    final b = path.getBounds();
    c.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.45, -0.55),
          radius: 1.25,
          colors: [_shade(base, 0.12), base, _shade(base, -0.16)],
          stops: const [0, 0.5, 1],
        ).createShader(b),
    );
    // Rim gelap lembut di sisi bawah untuk kesan volume.
    c.save();
    c.clipPath(path);
    c.drawPath(
      path.shift(Offset(0, -b.height * 0.08)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = b.shortestSide * 0.16
        ..color = _shade(base, -0.22).withValues(alpha: 0.35)
        ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, b.shortestSide * 0.08),
    );
    c.restore();
    if (gloss) {
      final g = Rect.fromCenter(
        center: Offset(b.left + b.width * 0.3, b.top + b.height * 0.24),
        width: b.width * 0.26 * glossScale,
        height: b.height * 0.13 * glossScale,
      );
      c.drawOval(
        g,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, b.shortestSide * 0.04 + 1),
      );
    }
  }

  Path rrect(double l, double t, double w, double h, double r) =>
      Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r)));

  Path oval(double cx, double cy, double w, double h) => Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));

  void coin(Canvas c, double cx, double cy, double r) {
    clay(c, oval(cx, cy + r * 0.12, r * 2, r * 2), _shade(gold, -0.12), gloss: false);
    clay(c, oval(cx, cy, r * 2, r * 2), gold);
    c.drawOval(
      Rect.fromCenter(center: Offset(cx, cy), width: r * 1.1, height: r * 1.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.18
        ..color = _shade(gold, -0.14).withValues(alpha: 0.7),
    );
  }

  void eyes(Canvas c, double cx, double cy, double gap) {
    final paint = Paint()..color = const Color(0xFF3B2A2E);
    c.drawOval(Rect.fromCenter(center: Offset(cx - gap, cy), width: 5, height: 7), paint);
    c.drawOval(Rect.fromCenter(center: Offset(cx + gap, cy), width: 5, height: 7), paint);
    final blushPaint = Paint()
      ..color = rose.withValues(alpha: 0.45)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 3);
    c.drawOval(Rect.fromCenter(center: Offset(cx - gap - 7, cy + 8), width: 10, height: 6), blushPaint);
    c.drawOval(Rect.fromCenter(center: Offset(cx + gap + 7, cy + 8), width: 10, height: 6), blushPaint);
  }

  double get floatA => math.sin((t + 0.25) * math.pi * 2) * 5;

  // ---------------------------------------------------------------------------
  // Ilustrasi

  void _jar(Canvas c) {
    // Koin yang melayang masuk ke toples.
    coin(c, 128, 28 + floatA, 13);
    clay(c, rrect(52, 58, 96, 112, 34), blush.withValues(alpha: 0.95));
    for (final (x, y) in [(78.0, 150.0), (104.0, 152.0), (124.0, 146.0), (90.0, 132.0), (114.0, 128.0)]) {
      coin(c, x, y, 13);
    }
    // Kaca: lapisan tipis di atas koin.
    c.drawPath(
      rrect(52, 58, 96, 112, 34),
      Paint()..color = Colors.white.withValues(alpha: 0.18),
    );
    clay(c, rrect(62, 46, 76, 22, 10), berry);
    clay(c, rrect(66, 104, 30, 8, 4), Colors.white.withValues(alpha: 0.6), gloss: false);
  }

  void _duo(Canvas c) {
    clay(c, rrect(34, 70, 72, 100, 36), sage);
    eyes(c, 70, 104, 11);
    clay(c, rrect(94, 58, 74, 112, 37), rose);
    eyes(c, 131, 94, 11);
    // Koin bersama di tengah, dipegang "tangan".
    coin(c, 101, 142 + floatA * 0.4, 15);
    clay(c, oval(84, 150, 18, 14), _shade(sage, 0.04), gloss: false);
    clay(c, oval(118, 150, 18, 14), _shade(rose, 0.04), gloss: false);
  }

  void _wallet(Canvas c) {
    clay(c, rrect(66, 40 + floatA, 70, 46, 10), sage);
    clay(c, rrect(80, 30 + floatA * 0.6, 70, 46, 10), apricot);
    clay(c, rrect(38, 70, 128, 96, 26), rose);
    clay(c, rrect(118, 100, 56, 38, 16), berry);
    clay(c, oval(140, 119, 14, 14), gold);
  }

  void _chart(Canvas c) {
    final heights = [46.0, 74.0, 58.0, 100.0];
    final colors = [blush, sage, apricot, rose];
    for (var i = 0; i < 4; i++) {
      final grow = (math.sin((t + i * 0.12) * math.pi * 2) * 4);
      final h = heights[i] + grow;
      clay(c, rrect(38 + i * 34, 166 - h, 26, h, 13), colors[i]);
    }
    coin(c, 152, 42 + floatA, 14);
  }

  void _travel(Canvas c) {
    clay(c, rrect(82, 44, 36, 26, 12), _shade(berry, -0.05));
    clay(c, rrect(90, 50, 20, 16, 6), p.isDark ? const Color(0xFF3A2A30) : cream, gloss: false);
    clay(c, rrect(44, 62, 112, 106, 26), rose);
    clay(c, rrect(62, 62, 14, 106, 6), _shade(rose, -0.08), gloss: false);
    clay(c, rrect(124, 62, 14, 106, 6), _shade(rose, -0.08), gloss: false);
    clay(c, oval(66, 170, 16, 12), moss, gloss: false);
    clay(c, oval(134, 170, 16, 12), moss, gloss: false);
    // Stiker bulat.
    clay(c, oval(100, 110 + floatA * 0.3, 30, 30), sage);
  }

  void _shield(Canvas c) {
    final path = Path()
      ..moveTo(100, 30)
      ..cubicTo(126, 42, 146, 44, 160, 44)
      ..cubicTo(160, 110, 140, 150, 100, 172)
      ..cubicTo(60, 150, 40, 110, 40, 44)
      ..cubicTo(54, 44, 74, 42, 100, 30)
      ..close();
    clay(c, path, sage);
    final inner = Path()
      ..moveTo(100, 52)
      ..cubicTo(116, 60, 128, 62, 138, 62)
      ..cubicTo(136, 108, 124, 136, 100, 152)
      ..cubicTo(76, 136, 64, 108, 62, 62)
      ..cubicTo(72, 62, 84, 60, 100, 52)
      ..close();
    clay(c, inner, _shade(sage, 0.08), glossScale: 0.7);
    coin(c, 100, 104 + floatA * 0.4, 18);
  }

  void _house(Canvas c) {
    clay(c, rrect(50, 86, 100, 84, 18), blush);
    final roof = Path()
      ..moveTo(100, 34)
      ..quadraticBezierTo(108, 34, 116, 40)
      ..lineTo(160, 80)
      ..quadraticBezierTo(166, 94, 150, 94)
      ..lineTo(50, 94)
      ..quadraticBezierTo(34, 94, 40, 80)
      ..lineTo(84, 40)
      ..quadraticBezierTo(92, 34, 100, 34)
      ..close();
    clay(c, roof, berry);
    clay(c, rrect(86, 122, 30, 48, 12), sage);
    clay(c, rrect(124, 108, 18, 18, 6), p.isDark ? const Color(0xFFF2C46B) : cream, gloss: false);
    coin(c, 58, 50 + floatA, 11);
  }

  void _gadget(Canvas c) {
    clay(c, rrect(62, 30, 76, 140, 22), _shade(berry, -0.02));
    clay(c, rrect(70, 42, 60, 110, 14), p.isDark ? const Color(0xFF4A3A40) : cream, gloss: false);
    clay(c, rrect(78, 56, 44, 30, 10), blush, gloss: false);
    clay(c, rrect(78, 94, 30, 10, 5), sage, gloss: false);
    clay(c, rrect(78, 110, 38, 10, 5), apricot, gloss: false);
    coin(c, 150, 60 + floatA, 13);
  }

  void _study(Canvas c) {
    clay(c, rrect(40, 136, 120, 30, 10), sage);
    clay(c, rrect(50, 108, 104, 30, 10), rose);
    clay(c, rrect(44, 80, 112, 30, 10), apricot);
    // Topi toga.
    final cap = Path()
      ..moveTo(100, 34 + floatA)
      ..lineTo(150, 54 + floatA)
      ..lineTo(100, 74 + floatA)
      ..lineTo(50, 54 + floatA)
      ..close();
    clay(c, rrect(78, 58 + floatA, 44, 22, 8), _shade(berry, -0.1), gloss: false);
    clay(c, cap, berry);
  }

  void _gift(Canvas c) {
    clay(c, rrect(48, 86, 104, 84, 18), rose);
    clay(c, rrect(40, 70, 120, 28, 12), berry);
    clay(c, rrect(92, 70, 16, 100, 6), apricot, gloss: false);
    final bowL = oval(84, 60 + floatA * 0.3, 34, 24);
    final bowR = oval(116, 60 + floatA * 0.3, 34, 24);
    clay(c, bowL, apricot);
    clay(c, bowR, apricot);
    clay(c, oval(100, 64 + floatA * 0.3, 16, 16), _shade(apricot, -0.06));
  }

  void _trophy(Canvas c) {
    // Konfeti bola-bola clay.
    final dots = [(34.0, 60.0, rose), (164.0, 48.0, sage), (150.0, 104.0, apricot), (46.0, 118.0, blush), (60.0, 36.0, apricot)];
    for (var i = 0; i < dots.length; i++) {
      final d = dots[i];
      final dy = math.sin((t + i * 0.2) * math.pi * 2) * 6;
      clay(c, oval(d.$1, d.$2 + dy, 12, 12), d.$3, glossScale: 1.2);
    }
    clay(c, rrect(70, 150, 60, 20, 8), berry);
    clay(c, rrect(92, 118, 16, 36, 6), _shade(gold, -0.1), gloss: false);
    final cup = Path()
      ..moveTo(62, 44)
      ..lineTo(138, 44)
      ..cubicTo(138, 100, 124, 122, 100, 124)
      ..cubicTo(76, 122, 62, 100, 62, 44)
      ..close();
    clay(c, oval(58, 66, 24, 30), _shade(gold, -0.08), gloss: false);
    clay(c, oval(142, 66, 24, 30), _shade(gold, -0.08), gloss: false);
    clay(c, cup, gold);
  }

  void _calendar(Canvas c) {
    clay(c, rrect(44, 52, 112, 118, 22), p.isDark ? const Color(0xFFE9DCDC) : cream);
    clay(c, rrect(44, 52, 112, 36, 18), rose, gloss: false);
    clay(c, rrect(72, 38, 12, 28, 6), berry);
    clay(c, rrect(116, 38, 12, 28, 6), berry);
    for (var r = 0; r < 2; r++) {
      for (var col = 0; col < 3; col++) {
        final hit = r == 1 && col == 1;
        clay(c, rrect(62 + col * 28.0, 102 + r * 28.0, 20, 18, 6), hit ? sage : blush.withValues(alpha: 0.7), gloss: hit);
      }
    }
    coin(c, 156, 44 + floatA, 12);
  }

  void _search(Canvas c) {
    c.save();
    c.translate(124, 122);
    c.rotate(-0.75);
    clay(c, rrect(-10, 0, 20, 56, 10), berry);
    c.restore();
    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCenter(center: const Offset(92, 88), width: 104, height: 104))
      ..addOval(Rect.fromCenter(center: const Offset(92, 88), width: 70, height: 70));
    clay(c, ring, rose);
    c.drawOval(
      Rect.fromCenter(center: const Offset(92, 88), width: 70, height: 70),
      Paint()..color = Colors.white.withValues(alpha: p.isDark ? 0.08 : 0.35),
    );
    coin(c, 92, 88 + floatA * 0.5, 12);
  }

  @override
  bool shouldRepaint(_ClayPainter old) => old.t != t || old.kind != kind || old.p != p;
}

/// Empty state: ilustrasi + judul + penjelasan singkat + aksi opsional.
class ClayEmpty extends StatelessWidget {
  const ClayEmpty({super.key, required this.kind, required this.title, required this.message, this.action, this.size = 150});
  final ClayKind kind;
  final String title;
  final String message;
  final Widget? action;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.lg, horizontal: AuraSpace.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AuraSparkle(child: ClayArt(kind, size: size)),
          const SizedBox(height: AuraSpace.sm),
          Text(title, style: AuraType.headlineSm.copyWith(color: p.onSurface), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: AuraSpace.md), action!],
        ],
      ),
    );
  }
}
