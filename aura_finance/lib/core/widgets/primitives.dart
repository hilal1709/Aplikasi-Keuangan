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
              duration: duration,
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
          duration: const Duration(milliseconds: 1100),
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

extension StaggerX on Widget {
  /// Entrance standar: naik 16px + fade, dengan jeda bertingkat per indeks.
  Widget staggerIn(int index, {int stepMs = 45, int baseMs = 0}) => _StaggerIn(delay: baseMs + index * stepMs, child: this);
}

class _StaggerIn extends StatefulWidget {
  const _StaggerIn({required this.delay, required this.child});
  final int delay;
  final Widget child;

  @override
  State<_StaggerIn> createState() => _StaggerInState();
}

class _StaggerInState extends State<_StaggerIn> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 560));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);

  @override
  void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _c.forward();
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
      builder: (context, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(offset: Offset(0, 16 * (1 - _a.value)), child: child),
      ),
    );
  }
}
