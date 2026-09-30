import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';

import '../icons/category_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'neu_surface.dart';
import 'primitives.dart';

class NeuIconButton extends StatefulWidget {
  const NeuIconButton(this.icon, {super.key, required this.onTap, this.size = 44, this.color, this.label});
  final HugeIconData icon;
  final VoidCallback? onTap;
  final double size;
  final Color? color;
  final String? label;

  @override
  State<NeuIconButton> createState() => _NeuIconButtonState();
}

class _NeuIconButtonState extends State<NeuIconButton> {
  int _taps = 0;

  @override
  Widget build(BuildContext context) {
    return NeuPressable(
      onTap: widget.onTap == null
          ? null
          : () {
              setState(() => _taps++);
              widget.onTap!();
            },
      circle: true,
      tilt: false,
      width: widget.size,
      height: widget.size,
      semanticLabel: widget.label,
      child: Center(
        // Ikon "membal" & berputar sedikit setiap kali diketuk.
        child: TweenAnimationBuilder<double>(
          key: ValueKey(_taps),
          tween: Tween(begin: _taps == 0 || Motion.reduced(context) ? 1 : 0, end: 1),
          duration: const Duration(milliseconds: 700),
          builder: (context, t, child) {
            final bounce = 1 - math.sin(t * math.pi) * 0.25 * (1 - t) - (1 - Curves.elasticOut.transform(t)) * 0.3;
            return Transform.rotate(
              angle: math.sin(t * math.pi * 2) * 0.35 * (1 - t),
              child: Transform.scale(scale: bounce, child: child),
            );
          },
          child: AuraIcon(widget.icon, size: widget.size * 0.45, color: widget.color),
        ),
      ),
    );
  }
}

/// Kerangka halaman sekunder: header besar yang mengecil saat digulir,
/// tombol kembali neumorph, dan konten berupa sliver.
class AuraPage extends StatelessWidget {
  const AuraPage({super.key, required this.title, required this.slivers, this.actions = const [], this.subtitle, this.floating});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? floating;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      floatingActionButton: floating,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _Header(title: title, subtitle: subtitle, actions: actions, top: top, palette: p),
          ),
          ...slivers,
          SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 40)),
        ],
      ),
    );
  }
}

class _Header extends SliverPersistentHeaderDelegate {
  _Header({required this.title, required this.subtitle, required this.actions, required this.top, required this.palette});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final double top;
  final AuraPalette palette;

  @override
  double get maxExtent => top + 132;
  @override
  double get minExtent => top + 72;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final t = (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0);
    final p = palette;
    // Bayangan muncul perlahan saat konten mulai tergulir di bawah header.
    final shadow = t;
    return Container(
      decoration: BoxDecoration(
        color: p.surface.withValues(alpha: 0.94),
        boxShadow: shadow == 0 ? null : [BoxShadow(color: p.shadowDark.withValues(alpha: p.shadowDark.a * 0.6 * shadow), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      padding: EdgeInsets.fromLTRB(AuraSpace.margin, top + 12, AuraSpace.margin, 8),
      child: Stack(
        children: [
          Row(
            children: [
              NeuIconButton(
                HugeIcons.strokeRoundedArrowLeft01,
                label: 'Kembali',
                onTap: () => context.canPop() ? context.pop() : context.go('/'),
              ),
              const Spacer(),
              for (final (i, a) in actions.indexed) Padding(padding: const EdgeInsets.only(left: 10), child: a.popIn(delayMs: 180 + i * 90)),
            ],
          ),
          // Judul berpindah dari bawah (besar) ke tengah atas (kecil).
          Align(
            alignment: Alignment.lerp(Alignment.bottomLeft, const Alignment(0, -0.6), t)!,
            child: Padding(
              padding: EdgeInsets.only(left: 4 + 52 * t, right: 52 * t),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: t > 0.5 ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  SplitReveal(
                    title,
                    delayMs: 120,
                    style: TextStyle.lerp(AuraType.headlineLg, AuraType.headlineSm, t)!.copyWith(color: p.onSurface),
                  ),
                  if (subtitle != null && t < 0.4)
                    Opacity(
                      opacity: 1 - t / 0.4,
                      child: Text(subtitle!, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)).staggerIn(0, baseMs: 380),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_Header old) =>
      old.title != title || old.subtitle != subtitle || old.top != top || old.palette != palette || old.actions != actions;
}
