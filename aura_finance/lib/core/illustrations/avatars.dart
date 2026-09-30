import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Avatar ilustrasi kartun bergaya clay. Disimpan sebagai kunci string
/// (`avatar_1` …) supaya bisa disinkronkan ke profil tanpa mengunggah foto.
enum HairStyle { long, short, hijab, bun, curly, bob, beard, cap, ponytail, none }

enum Critter { none, cat, bear }

@immutable
class AvatarSpec {
  const AvatarSpec({
    required this.key,
    required this.label,
    required this.bg,
    required this.skin,
    required this.hair,
    required this.hairColor,
    required this.shirt,
    this.glasses = false,
    this.critter = Critter.none,
  });

  final String key;
  final String label;
  final Color bg;
  final Color skin;
  final HairStyle hair;
  final Color hairColor;
  final Color shirt;
  final bool glasses;
  final Critter critter;
}

const _light = Color(0xFFF7D4BC);
const _medium = Color(0xFFE2AE88);
const _tan = Color(0xFFC98D66);
const _deep = Color(0xFF8E5B3E);

const avatarSpecs = <AvatarSpec>[
  AvatarSpec(key: 'avatar_1', label: 'Rambut panjang', bg: Color(0xFFFFC6DA), skin: _light, hair: HairStyle.long, hairColor: Color(0xFF4A2E2A), shirt: Color(0xFFFE64A3)),
  AvatarSpec(key: 'avatar_2', label: 'Rambut pendek', bg: Color(0xFFD9E2C1), skin: _tan, hair: HairStyle.short, hairColor: Color(0xFF2B2021), shirt: Color(0xFF7C8C6E)),
  AvatarSpec(key: 'avatar_3', label: 'Hijab rose', bg: Color(0xFFFCE0CC), skin: _medium, hair: HairStyle.hijab, hairColor: Color(0xFFE88BA8), shirt: Color(0xFFC0306F)),
  AvatarSpec(key: 'avatar_4', label: 'Cepol & kacamata', bg: Color(0xFFE4D6EE), skin: _light, hair: HairStyle.bun, hairColor: Color(0xFF6B3E2E), shirt: Color(0xFFB795C9), glasses: true),
  AvatarSpec(key: 'avatar_5', label: 'Keriting', bg: Color(0xFFCFE3E6), skin: _deep, hair: HairStyle.curly, hairColor: Color(0xFF1F1718), shirt: Color(0xFF6E9AA3)),
  AvatarSpec(key: 'avatar_6', label: 'Bob', bg: Color(0xFFFFD9D6), skin: _tan, hair: HairStyle.bob, hairColor: Color(0xFF3A2521), shirt: Color(0xFFFEACA8)),
  AvatarSpec(key: 'avatar_7', label: 'Berjenggot', bg: Color(0xFFE3E7D2), skin: _medium, hair: HairStyle.beard, hairColor: Color(0xFF33251F), shirt: Color(0xFF5A6245)),
  AvatarSpec(key: 'avatar_8', label: 'Topi', bg: Color(0xFFFFEBD8), skin: _light, hair: HairStyle.cap, hairColor: Color(0xFFAF2365), shirt: Color(0xFFE7A977)),
  AvatarSpec(key: 'avatar_9', label: 'Hijab sage', bg: Color(0xFFF5E4E4), skin: _tan, hair: HairStyle.hijab, hairColor: Color(0xFF979F7E), shirt: Color(0xFF5A6245)),
  AvatarSpec(key: 'avatar_10', label: 'Kuncir', bg: Color(0xFFFFE3C4), skin: _medium, hair: HairStyle.ponytail, hairColor: Color(0xFF5B3524), shirt: Color(0xFFC98B6B)),
  AvatarSpec(key: 'avatar_11', label: 'Kucing', bg: Color(0xFFFFD6E5), skin: Color(0xFFF4B77E), hair: HairStyle.none, hairColor: Color(0xFFD98C4E), shirt: Color(0xFFFE64A3), critter: Critter.cat),
  AvatarSpec(key: 'avatar_12', label: 'Beruang', bg: Color(0xFFDDE6CB), skin: Color(0xFFB98563), hair: HairStyle.none, hairColor: Color(0xFF8E5B3E), shirt: Color(0xFF979F7E), critter: Critter.bear),
];

AvatarSpec? avatarSpec(String? key) => avatarSpecs.where((a) => a.key == key).firstOrNull;

/// Avatar bulat. Jika [avatarKey] null, tampil inisial dari [name] di atas gradien [fallbackColor].
class AuraAvatar extends StatelessWidget {
  const AuraAvatar({super.key, required this.avatarKey, this.name = '', this.size = 48, this.fallbackColor = const Color(0xFFFE64A3), this.ring});
  final String? avatarKey;
  final String name;
  final double size;
  final Color fallbackColor;
  final Color? ring;

  @override
  Widget build(BuildContext context) {
    final spec = avatarSpec(avatarKey);
    final shadow = BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: size * 0.16, offset: Offset(size * 0.04, size * 0.06));
    final border = ring == null ? null : Border.all(color: ring!, width: math.max(2, size * 0.05));
    if (spec == null) {
      final initials = name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: border,
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color.lerp(fallbackColor, Colors.white, 0.25)!, fallbackColor]),
          boxShadow: [shadow],
        ),
        child: Center(child: Text(initials.isEmpty ? '?' : initials, style: TextStyle(color: Colors.white, fontSize: size * 0.34, fontWeight: FontWeight.w700))),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, border: border, boxShadow: [shadow]),
      child: ClipOval(child: RepaintBoundary(child: CustomPaint(painter: _AvatarPainter(spec)))),
    );
  }
}

class _AvatarPainter extends CustomPainter {
  _AvatarPainter(this.a);
  final AvatarSpec a;

  Color _shade(Color c, double amount) {
    final hsl = HSLColor.fromColor(c);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  void _clay(Canvas c, Path path, Color base, {bool gloss = true}) {
    final b = path.getBounds();
    c.drawPath(
      path,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.2,
          colors: [_shade(base, 0.1), base, _shade(base, -0.13)],
          stops: const [0, 0.55, 1],
        ).createShader(b),
    );
    if (gloss) {
      c.drawOval(
        Rect.fromCenter(center: Offset(b.left + b.width * 0.3, b.top + b.height * 0.22), width: b.width * 0.22, height: b.height * 0.1),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, b.shortestSide * 0.03 + 0.5),
      );
    }
  }

  Path _oval(double cx, double cy, double w, double h) => Path()..addOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: h));
  Path _rr(double l, double t, double w, double h, double r) => Path()..addRRect(RRect.fromRectAndRadius(Rect.fromLTWH(l, t, w, h), Radius.circular(r)));

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 100);
    final c = canvas;

    // Latar.
    c.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()
        ..shader = RadialGradient(center: const Alignment(-0.3, -0.4), radius: 1.1, colors: [_shade(a.bg, 0.05), a.bg, _shade(a.bg, -0.06)])
            .createShader(const Rect.fromLTWH(0, 0, 100, 100)),
    );

    if (a.critter != Critter.none) {
      _critter(c);
      return;
    }

    // Rambut belakang (di balik kepala).
    switch (a.hair) {
      case HairStyle.long:
        _clay(c, _rr(24, 26, 52, 62, 24), a.hairColor, gloss: false);
      case HairStyle.hijab:
        _clay(c, _oval(50, 58, 66, 78), a.hairColor);
      case HairStyle.bob:
        _clay(c, _rr(26, 24, 48, 46, 22), a.hairColor, gloss: false);
      case HairStyle.curly:
        for (final (x, y, r) in [(30.0, 36.0, 12.0), (70.0, 36.0, 12.0), (34.0, 24.0, 12.0), (66.0, 24.0, 12.0), (50.0, 18.0, 14.0), (27.0, 50.0, 10.0), (73.0, 50.0, 10.0)]) {
          _clay(c, _oval(x, y, r * 2, r * 2), a.hairColor, gloss: false);
        }
      case HairStyle.ponytail:
        _clay(c, _oval(74, 44, 16, 30), a.hairColor, gloss: false);
      default:
        break;
    }

    // Badan & leher.
    _clay(c, _rr(18, 76, 64, 40, 26), a.shirt);
    _clay(c, _rr(43, 62, 14, 18, 6), _shade(a.skin, -0.05), gloss: false);

    // Telinga & kepala.
    if (a.hair != HairStyle.hijab) {
      _clay(c, _oval(29, 50, 9, 12), _shade(a.skin, -0.03), gloss: false);
      _clay(c, _oval(71, 50, 9, 12), _shade(a.skin, -0.03), gloss: false);
    }
    _clay(c, _oval(50, 47, 40, 44), a.skin);

    // Rambut depan / aksesori kepala.
    switch (a.hair) {
      case HairStyle.long:
      case HairStyle.bob:
        final fringe = Path()
          ..moveTo(29, 46)
          ..quadraticBezierTo(30, 22, 50, 22)
          ..quadraticBezierTo(70, 22, 71, 46)
          ..quadraticBezierTo(62, 34, 50, 34)
          ..quadraticBezierTo(38, 32, 29, 46)
          ..close();
        _clay(c, fringe, a.hairColor);
      case HairStyle.short:
      case HairStyle.beard:
        final top = Path()
          ..moveTo(30, 44)
          ..quadraticBezierTo(28, 22, 50, 22)
          ..quadraticBezierTo(72, 22, 70, 44)
          ..quadraticBezierTo(66, 32, 54, 32)
          ..quadraticBezierTo(40, 30, 30, 44)
          ..close();
        _clay(c, top, a.hairColor);
      case HairStyle.hijab:
        // Bingkai wajah hijab.
        final frame = Path()
          ..fillType = PathFillType.evenOdd
          ..addOval(Rect.fromCenter(center: const Offset(50, 48), width: 50, height: 56))
          ..addOval(Rect.fromCenter(center: const Offset(50, 50), width: 36, height: 42));
        _clay(c, frame, a.hairColor);
      case HairStyle.bun:
        _clay(c, _oval(50, 20, 18, 16), a.hairColor);
        final top = Path()
          ..moveTo(30, 44)
          ..quadraticBezierTo(30, 24, 50, 25)
          ..quadraticBezierTo(70, 24, 70, 44)
          ..quadraticBezierTo(60, 33, 50, 33)
          ..quadraticBezierTo(40, 33, 30, 44)
          ..close();
        _clay(c, top, a.hairColor);
      case HairStyle.curly:
        for (final (x, y) in [(38.0, 28.0), (50.0, 26.0), (62.0, 28.0)]) {
          _clay(c, _oval(x, y, 16, 14), a.hairColor, gloss: false);
        }
      case HairStyle.cap:
        _clay(c, _rr(28, 20, 44, 18, 12), a.hairColor);
        _clay(c, _rr(46, 32, 34, 7, 4), _shade(a.hairColor, -0.08), gloss: false);
      case HairStyle.ponytail:
        final top = Path()
          ..moveTo(30, 44)
          ..quadraticBezierTo(30, 23, 50, 23)
          ..quadraticBezierTo(70, 23, 70, 44)
          ..quadraticBezierTo(58, 30, 42, 34)
          ..quadraticBezierTo(34, 36, 30, 44)
          ..close();
        _clay(c, top, a.hairColor);
      case HairStyle.none:
        break;
    }

    if (a.hair == HairStyle.beard) {
      final beard = Path()
        ..moveTo(32, 50)
        ..quadraticBezierTo(34, 72, 50, 72)
        ..quadraticBezierTo(66, 72, 68, 50)
        ..quadraticBezierTo(60, 60, 50, 58)
        ..quadraticBezierTo(40, 60, 32, 50)
        ..close();
      _clay(c, beard, a.hairColor, gloss: false);
    }

    _face(c, beard: a.hair == HairStyle.beard);
    if (a.glasses) _glasses(c);
  }

  void _face(Canvas c, {bool beard = false}) {
    final ink = Paint()..color = const Color(0xFF2E2124);
    c.drawOval(Rect.fromCenter(center: const Offset(42, 49), width: 4.2, height: 5.4), ink);
    c.drawOval(Rect.fromCenter(center: const Offset(58, 49), width: 4.2, height: 5.4), ink);
    final shine = Paint()..color = Colors.white;
    c.drawCircle(const Offset(42.8, 48), 0.9, shine);
    c.drawCircle(const Offset(58.8, 48), 0.9, shine);
    final blush = Paint()
      ..color = const Color(0xFFFE7FB2).withValues(alpha: 0.35)
      ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 2);
    c.drawOval(Rect.fromCenter(center: const Offset(36, 56), width: 8, height: 4.5), blush);
    c.drawOval(Rect.fromCenter(center: const Offset(64, 56), width: 8, height: 4.5), blush);
    final smile = Paint()
      ..color = beard ? const Color(0xFFF7D4BC) : const Color(0xFF7A3B45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round;
    c.drawArc(Rect.fromCenter(center: const Offset(50, 56), width: 9, height: 6), 0.3, math.pi - 0.6, false, smile);
  }

  void _glasses(Canvas c) {
    final p = Paint()
      ..color = const Color(0xFF3B2A2E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    c.drawCircle(const Offset(42, 49), 6.5, p);
    c.drawCircle(const Offset(58, 49), 6.5, p);
    c.drawLine(const Offset(48.5, 49), const Offset(51.5, 49), p);
  }

  void _critter(Canvas c) {
    _clay(c, _rr(20, 78, 60, 40, 26), a.shirt);
    if (a.critter == Critter.cat) {
      for (final dx in [-1.0, 1.0]) {
        final ear = Path()
          ..moveTo(50 + dx * 10, 32)
          ..lineTo(50 + dx * 21, 16)
          ..lineTo(50 + dx * 24, 38)
          ..close();
        _clay(c, ear, a.skin);
        final inner = Path()
          ..moveTo(50 + dx * 13, 32)
          ..lineTo(50 + dx * 20, 22)
          ..lineTo(50 + dx * 21, 35)
          ..close();
        c.drawPath(inner, Paint()..color = const Color(0xFFFFB9B4));
      }
    } else {
      _clay(c, _oval(32, 28, 16, 16), a.skin);
      _clay(c, _oval(68, 28, 16, 16), a.skin);
      c.drawOval(Rect.fromCenter(center: const Offset(32, 28), width: 8, height: 8), Paint()..color = _shade(a.skin, 0.12));
      c.drawOval(Rect.fromCenter(center: const Offset(68, 28), width: 8, height: 8), Paint()..color = _shade(a.skin, 0.12));
    }
    _clay(c, _oval(50, 50, 48, 44), a.skin);
    if (a.critter == Critter.cat) {
      // Belang.
      final stripe = Paint()
        ..color = a.hairColor.withValues(alpha: 0.7)
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      c.drawLine(const Offset(50, 29), const Offset(50, 36), stripe);
      c.drawLine(const Offset(44, 30), const Offset(45, 35), stripe);
      c.drawLine(const Offset(56, 30), const Offset(55, 35), stripe);
    }
    _clay(c, _oval(50, 58, 20, 14), _shade(a.skin, 0.14), gloss: false);
    _face(c);
    c.drawOval(Rect.fromCenter(center: const Offset(50, 54.5), width: 5, height: 3.5), Paint()..color = const Color(0xFF5A3A36));
    if (a.critter == Critter.cat) {
      final whisker = Paint()
        ..color = const Color(0xFF5A3A36).withValues(alpha: 0.6)
        ..strokeWidth = 1;
      for (final dx in [-1.0, 1.0]) {
        c.drawLine(Offset(50 + dx * 8, 57), Offset(50 + dx * 20, 55), whisker);
        c.drawLine(Offset(50 + dx * 8, 59), Offset(50 + dx * 20, 60), whisker);
      }
    }
  }

  @override
  bool shouldRepaint(_AvatarPainter old) => old.a != a;
}
