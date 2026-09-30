import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../icons/category_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/rupiah.dart';
import 'neu_surface.dart';

/// Ikon Hugeicons dengan default ukuran & ketebalan garis aplikasi.
class AuraIcon extends StatelessWidget {
  const AuraIcon(this.icon, {super.key, this.size = 22, this.color, this.strokeWidth = 1.6});
  final HugeIconData icon;
  final double size;
  final Color? color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) =>
      HugeIcon(icon: icon, size: size, color: color ?? context.aura.onSurfaceVariant, strokeWidth: strokeWidth);
}

/// Nominal rupiah yang "bergulir" dari nilai lama ke nilai baru,
/// dan tersamar (blur) saat mode sembunyikan saldo aktif.
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.style,
    this.hidden = false,
    this.compact = false,
    this.signed = false,
    this.duration = const Duration(milliseconds: 900),
  });

  final int value;
  final TextStyle? style;
  final bool hidden;
  final bool compact;
  final bool signed;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) => AnimatedBuilder(
        animation: anim,
        child: child,
        builder: (context, child) {
          // Filter blur & opacity hanya dipasang selama transisi: lapisan offscreen
          // yang selalu ada membuat setiap angka rupiah mahal digambar tiap frame.
          if (anim.value >= 1) return child!;
          final sigma = (1 - anim.value) * 8;
          return Opacity(
            opacity: anim.value,
            child: ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child),
          );
        },
      ),
      layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
      child: hidden
          ? Text('Rp ••••••', key: const ValueKey('hidden'), style: style, maxLines: 1)
          : TweenAnimationBuilder<double>(
              key: const ValueKey('shown'),
              tween: Tween(end: value.toDouble()),
              duration: Motion.reduced(context) ? Duration.zero : duration,
              curve: Curves.easeOutExpo,
              builder: (context, v, _) {
                final n = v.round();
                final text = compact ? Rupiah.compact(n, signed: signed) : Rupiah.format(n, signed: signed);
                return Text(
                  text,
                  style: (style ?? const TextStyle()).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
    );
  }
}

/// Wadah ikon kategori: lubang cekung dengan ikon berwarna nada kategori.
class CategoryBadge extends StatelessWidget {
  const CategoryBadge({super.key, required this.icon, required this.color, this.size = 48});
  final String icon;
  final int color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tone = Color(color);
    return NeuSurface(
      depth: -0.8,
      radius: size * 0.36,
      width: size,
      height: size,
      color: context.aura.surfaceContainer,
      child: Center(child: AuraIcon(categoryIcon(icon), size: size * 0.46, color: tone, strokeWidth: 1.8)),
    );
  }
}

/// Trek progres cekung dengan isian yang memantul (spring) saat nilainya berubah.
class NeuProgress extends StatelessWidget {
  const NeuProgress({super.key, required this.value, this.height = 12, this.colors, this.warn = false});
  final double value;
  final double height;
  final List<Color>? colors;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final fill = colors ?? (warn ? [p.secondary, p.secondaryContainer] : [p.primaryContainer, p.secondaryContainer]);
    return NeuSurface(
      depth: -1,
      radius: AuraRadius.pill,
      height: height,
      color: p.surfaceContainer,
      padding: const EdgeInsets.all(2),
      child: LayoutBuilder(
        builder: (context, box) => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: value.clamp(0, 1)),
          duration: Motion.reduced(context) ? Duration.zero : const Duration(milliseconds: 1100),
          curve: Curves.elasticOut,
          builder: (context, v, _) => Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: (box.maxWidth * v.clamp(0, 1)).clamp(height - 4, box.maxWidth),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AuraRadius.pill),
                gradient: LinearGradient(colors: fill),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kontrol segmen dengan "pil" timbul yang meluncur di dalam trek cekung.
class NeuSegmented<T> extends StatelessWidget {
  const NeuSegmented({super.key, required this.value, required this.options, required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final keys = options.keys.toList();
    final index = keys.indexOf(value);
    return NeuSurface(
      depth: -1,
      radius: AuraRadius.pill,
      color: p.surfaceContainer,
      padding: const EdgeInsets.all(4),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / keys.length;
          return SizedBox(
            height: 32,
            child: Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutBack,
                  left: w * index,
                  width: w,
                  top: 0,
                  bottom: 0,
                  child: NeuSurface(depth: 0.6, radius: AuraRadius.pill, color: p.surfaceLowest),
                ),
                Row(
                  children: [
                    for (final k in keys)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (k == value) return;
                            HapticFeedback.selectionClick();
                            onChanged(k);
                          },
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 220),
                              style: AuraType.labelMd.copyWith(
                                color: k == value ? p.primary : p.onSurfaceVariant,
                                fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                              ),
                              child: Text(options[k]!),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.trailing, this.subtitle});
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AuraType.headlineSm.copyWith(color: p.onSurface)),
                if (subtitle != null) Text(subtitle!, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Tautan teks kecil berbentuk pil timbul ("Lihat semua").
class PillLink extends StatelessWidget {
  const PillLink(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuPressable(
      onTap: onTap,
      radius: AuraRadius.pill,
      color: p.surfaceContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(label, style: AuraType.labelMd.copyWith(color: p.primary)),
    );
  }
}

/// Durasi & kurva animasi bersama, plus penghormatan pada "Remove animations" OS.
class Motion {
  Motion._();
  static const fast = Duration(milliseconds: 220);
  static const base = Duration(milliseconds: 420);
  static const slow = Duration(milliseconds: 700);
  static const expo = Curves.easeOutExpo;
  static const back = Curves.easeOutBack;

  /// Durasi & kurva entrance ala GSAP (`duration: 1, ease: 'power3.out'`).
  /// Expo terlalu cepat terasa selesai (90% gerak di sepertiga awal), quart lebih "mengalir".
  static const enter = Duration(milliseconds: 1000);
  static const power3 = Curves.easeOutQuart;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;
}

extension StaggerX on Widget {
  /// Entrance standar: naik + fade + sedikit membesar, dengan jeda bertingkat per indeks.
  /// Jeda dibatasi [_maxSteps] langkah: item yang baru dibangun saat daftar digulir
  /// langsung beranimasi, tidak menunggu antrean indeksnya.
  Widget staggerIn(int index, {int stepMs = 70, int baseMs = 0}) =>
      _StaggerIn(delay: baseMs + math.min(index, _maxSteps) * stepMs, child: this);

  /// Muncul membal (scale + fade) — untuk centang, lencana, dan elemen kecil.
  Widget popIn({int delayMs = 0}) => _PopIn(delay: delayMs, child: this);

  /// Masuk dari samping (mis. item daftar), bertingkat per indeks.
  Widget slideInX(int index, {double dx = 60, int stepMs = 70}) =>
      _StaggerIn(delay: math.min(index, _maxSteps) * stepMs, dx: dx, dy: 0, child: this);

  /// Muncul saat masuk layar (seperti GSAP ScrollTrigger), bukan saat dibangun.
  Widget reveal({int delayMs = 0, double dy = 80, double scale = 0.9}) =>
      ScrollReveal(delayMs: delayMs, dy: dy, scale: scale, child: this);

  /// Kilau cahaya yang menyapu sekali (kartu, lencana).
  Widget shimmerOnce({int delayMs = 400, Color? color, double radius = 0}) =>
      _Shimmer(delayMs: delayMs, color: color, radius: radius, child: this);
}

const _maxSteps = 6;

/// Animasi dipicu posisi scroll: mulai saat bagian atas elemen melewati
/// [trigger] × tinggi layar (default 92%), lalu tidak diulang.
class ScrollReveal extends StatefulWidget {
  const ScrollReveal({super.key, required this.child, this.delayMs = 0, this.dy = 80, this.scale = 0.9, this.trigger = 0.9});
  final Widget child;
  final int delayMs;
  final double dy;
  final double scale;
  final double trigger;

  @override
  State<ScrollReveal> createState() => _ScrollRevealState();
}

class _ScrollRevealState extends State<ScrollReveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Motion.power3);
  ScrollPosition? _pos;
  bool _fired = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _fire(immediate: true);
      return;
    }
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos != _pos) {
      _pos?.removeListener(_schedule);
      _pos = pos;
      if (!_fired) _pos?.addListener(_schedule);
    }
    _schedule();
  }

  bool _pending = false;

  // Listener scroll dipanggil sebelum layout diperbarui: ukur posisi setelah frame selesai.
  void _schedule() {
    if (_pending || _fired) return;
    _pending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pending = false;
      _check();
    });
  }

  void _check() {
    if (_fired || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top < MediaQuery.sizeOf(context).height * widget.trigger) _fire();
  }

  void _fire({bool immediate = false}) {
    if (_fired) return;
    _fired = true;
    _pos?.removeListener(_schedule);
    if (immediate) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _pos?.removeListener(_schedule);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) {
          final t = _a.value;
          return Opacity(
            opacity: t.clamp(0, 1),
            child: Transform.translate(
              offset: Offset(0, widget.dy * (1 - t)),
              child: Transform.scale(scale: widget.scale + (1 - widget.scale) * t, child: child),
            ),
          );
        },
      );
}

/// Parallax terikat scroll (seperti GSAP `scrub`): elemen bergerak lebih lambat
/// dari konten, mengecil & memudar saat digulir menjauh; membesar sedikit saat ditarik.
class ScrollParallax extends StatelessWidget {
  const ScrollParallax({super.key, required this.child, this.factor = 0.35, this.fadeOver = 360, this.minScale = 0.92});
  final Widget child;
  final double factor;
  final double fadeOver;
  final double minScale;

  @override
  Widget build(BuildContext context) {
    final pos = Scrollable.maybeOf(context)?.position;
    if (pos == null || Motion.reduced(context)) return child;
    return AnimatedBuilder(
      animation: pos,
      child: child,
      builder: (context, child) {
        final px = pos.hasPixels ? pos.pixels : 0.0;
        if (px <= 0) {
          return Transform.scale(scale: 1 + (-px / 900).clamp(0.0, 0.08), child: child);
        }
        final t = (px / fadeOver).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, px * factor),
          child: Transform.scale(
            scale: 1 - (1 - minScale) * t,
            child: Opacity(opacity: 1 - 0.7 * t, child: child),
          ),
        );
      },
    );
  }
}

/// Teks yang muncul per huruf (seperti GSAP SplitText): tiap huruf naik,
/// sedikit berputar dan memudar masuk secara bertingkat.
class SplitReveal extends StatefulWidget {
  const SplitReveal(this.text, {super.key, this.style, this.delayMs = 0, this.stepMs = 45, this.maxLines = 1});
  final String text;
  final TextStyle? style;
  final int delayMs;
  final int stepMs;
  final int maxLines;

  @override
  State<SplitReveal> createState() => _SplitRevealState();
}

class _SplitRevealState extends State<SplitReveal> with SingleTickerProviderStateMixin {
  static const _charMs = 800;
  late final String _text = widget.text;
  late final List<String> _chars = _text.characters.toList();
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _charMs + widget.stepMs * math.max(0, _chars.length - 1)),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final plain = Text(widget.text, style: widget.style, maxLines: widget.maxLines, overflow: TextOverflow.ellipsis);
    // Teks berubah, atau animasi selesai: pakai teks biasa agar kerning & ellipsis rapi.
    if (widget.text != _text) return plain;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        if (_c.isCompleted) return plain;
        final nowMs = _c.value * _c.duration!.inMilliseconds;
        return Text.rich(
          TextSpan(children: [
            for (final (i, ch) in _chars.indexed)
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: _SplitChar(ch, style: widget.style, t: ((nowMs - i * widget.stepMs) / _charMs).clamp(0.0, 1.0)),
              ),
          ]),
          maxLines: widget.maxLines,
          overflow: TextOverflow.clip,
        );
      },
    );
  }
}

class _SplitChar extends StatelessWidget {
  const _SplitChar(this.ch, {required this.t, this.style});
  final String ch;
  final double t;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final e = Curves.easeOutBack.transform(t);
    return Opacity(
      opacity: Curves.easeOut.transform(t),
      child: Transform.translate(
        offset: Offset(0, 30 * (1 - e)),
        child: Transform.rotate(angle: 0.45 * (1 - e), alignment: Alignment.bottomLeft, child: Text(ch, style: style)),
      ),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.delayMs, required this.child, this.color, this.radius = 0});
  final int delayMs;
  final Color? color;
  final double radius;
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) return;
    Future.delayed(Duration(milliseconds: widget.delayMs), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          if (!_c.isAnimating) return child!;
          return ShimmerSweep(t: Curves.easeInOutCubic.transform(_c.value), color: widget.color, radius: widget.radius, child: child!);
        },
      );
}

/// Pita cahaya miring di posisi [t] (0 = kiri luar, 1 = kanan luar), dilapis di atas [child].
class ShimmerSweep extends StatelessWidget {
  const ShimmerSweep({super.key, required this.t, required this.child, this.color, this.width = 0.22, this.radius = 0});
  final double t;
  final Widget child;
  final Color? color;
  final double width;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final light = color ?? Colors.white.withValues(alpha: 0.4);
    final c = -width + t * (1 + 2 * width);
    return Stack(
      fit: StackFit.passthrough,
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-1, -0.5),
                    end: const Alignment(1, 0.5),
                    colors: [light.withValues(alpha: 0), light, light.withValues(alpha: 0)],
                    stops: [(c - width).clamp(0.0, 1.0), c.clamp(0.0, 1.0), (c + width).clamp(0.0, 1.0)],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bergoyang horizontal sekali tiap [trigger] bertambah (validasi gagal).
class ShakeX extends StatefulWidget {
  const ShakeX({super.key, required this.trigger, required this.child});
  final int trigger;
  final Widget child;

  @override
  State<ShakeX> createState() => _ShakeXState();
}

class _ShakeXState extends State<ShakeX> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));

  @override
  void didUpdateWidget(ShakeX old) {
    super.didUpdateWidget(old);
    if (widget.trigger != old.trigger && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final t = _c.value;
          final dx = math.sin(t * math.pi * 5) * (1 - t) * 9;
          return Transform.translate(offset: Offset(dx, 0), child: child);
        },
      );
}

class _PopIn extends StatefulWidget {
  const _PopIn({required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  State<_PopIn> createState() => _PopInState();
}

class _PopInState extends State<_PopIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _c.value = 1;
    } else {
      Future.delayed(Duration(milliseconds: widget.delay), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        child: widget.child,
        builder: (context, child) {
          final s = Curves.elasticOut.transform(_c.value);
          return Opacity(
            opacity: Curves.easeOut.transform((_c.value * 2).clamp(0, 1)),
            child: Transform.scale(scale: 0.4 + 0.6 * s, child: child),
          );
        },
      );
}

class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.delay, required this.child, this.dx = 0, this.dy = 56});
  final int delay;
  final double dx;
  final double dy;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.enter);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Motion.power3);
  bool? _active;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab (IndexedStack) & halaman di bawah rute lain dimatikan lewat TickerMode.
    // Saat aktif lagi, entrance diputar ulang — seperti timeline GSAP yang di-restart.
    final active = TickerMode.valuesOf(context).enabled;
    if (active == _active) return;
    _active = active;
    if (!active) return;
    if (Motion.reduced(context)) {
      _c.value = 1;
      return;
    }
    _c.value = 0;
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted && _active == true) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _a,
      child: widget.child,
      builder: (context, child) {
        final t = _a.value;
        return Opacity(
          opacity: Curves.easeOut.transform(t.clamp(0, 1)),
          child: Transform.translate(
            offset: Offset(widget.dx * (1 - t), widget.dy * (1 - t)),
            child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
          ),
        );
      },
    );
  }
}
