import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';

import '../icons/category_icons.dart';
import '../illustrations/clay.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'neu_surface.dart';
import 'primitives.dart';

/// Nada umpan balik — menentukan warna aksen & ikon.
enum AuraTone { success, error, info, warning }

extension on AuraTone {
  (Color, Color, HugeIconData) colors(AuraPalette p) => switch (this) {
        // Centang hanya dipakai untuk makna "berhasil/selesai".
        AuraTone.success => (p.tertiary, p.tertiaryFixed, HugeIcons.strokeRoundedCheckmarkCircle02),
        AuraTone.error => (p.error, p.secondaryFixed, HugeIcons.strokeRoundedAlert02),
        AuraTone.warning => (const Color(0xFFB8732E), const Color(0xFFFCE3CC), HugeIcons.strokeRoundedAlert02),
        AuraTone.info => (p.primary, p.primaryFixed, HugeIcons.strokeRoundedInformationCircle),
      };
}

// =============================================================================
// Toast

/// Toast mengambang dari atas: jatuh dengan pegas, garis waktu menyusut di bawahnya,
/// bisa diusap ke atas / diketuk untuk menutup, dan punya aksi opsional (mis. "Urungkan").
/// Hanya satu toast tampil; toast baru menggantikan yang lama dengan animasi keluar.
abstract final class AuraToast {
  static _ToastEntry? _current;

  /// Overlay utama aplikasi. Diingat supaya toast tetap bisa tampil walau widget
  /// pemanggilnya sudah hilang (mis. kartu yang baru digeser untuk dihapus, atau
  /// tagihan yang pindah dari "lunas" ke "belum dibayar").
  static OverlayState? _root;

  /// Dipanggil sekali dari kerangka aplikasi.
  static void attach(BuildContext context) => _root = Overlay.maybeOf(context, rootOverlay: true) ?? _root;

  static void show(
    BuildContext context, {
    required String title,
    String? message,
    AuraTone tone = AuraTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Widget? leading,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    final overlay = (context.mounted ? Overlay.maybeOf(context, rootOverlay: true) : null) ?? _root;
    if (overlay == null || !overlay.mounted) return;
    _root = overlay;
    _current?.dismiss();
    switch (tone) {
      case AuraTone.error:
        HapticFeedback.heavyImpact();
      case AuraTone.success:
        HapticFeedback.mediumImpact();
      default:
        HapticFeedback.lightImpact();
    }
    late final _ToastEntry entry;
    entry = _ToastEntry(
      OverlayEntry(
        builder: (_) => _ToastView(
          key: entry.key,
          title: title,
          message: message,
          tone: tone,
          actionLabel: actionLabel,
          onAction: onAction,
          leading: leading,
          duration: duration,
          onGone: () {
            entry.overlay.remove();
            if (identical(_current, entry)) _current = null;
          },
        ),
      ),
    );
    _current = entry;
    overlay.insert(entry.overlay);
  }

  /// Toast di overlay utama tanpa bergantung pada `context` pemanggil — untuk aksi
  /// setelah `await` yang membuat widget pemanggilnya hilang.
  static void global({
    required String title,
    String? message,
    AuraTone tone = AuraTone.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = const Duration(milliseconds: 3200),
  }) {
    final root = _root;
    if (root == null || !root.mounted) return;
    show(root.context, title: title, message: message, tone: tone, actionLabel: actionLabel, onAction: onAction, duration: duration);
  }

  static void success(BuildContext c, String title, {String? message}) => show(c, title: title, message: message, tone: AuraTone.success);
  static void error(BuildContext c, String title, {String? message}) => show(c, title: title, message: message, tone: AuraTone.error);
  static void info(BuildContext c, String title, {String? message}) => show(c, title: title, message: message);

  static void hide() => _current?.dismiss();
}

class _ToastEntry {
  _ToastEntry(this.overlay);
  final OverlayEntry overlay;
  final key = GlobalKey<_ToastViewState>();
  void dismiss() => key.currentState?.dismiss();
}

class _ToastView extends StatefulWidget {
  const _ToastView({
    super.key,
    required this.title,
    required this.message,
    required this.tone,
    required this.actionLabel,
    required this.onAction,
    required this.leading,
    required this.duration,
    required this.onGone,
  });
  final String title;
  final String? message;
  final AuraTone tone;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Widget? leading;
  final Duration duration;
  final VoidCallback onGone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 620), reverseDuration: const Duration(milliseconds: 260))
    ..forward();
  late final AnimationController _timer = AnimationController(vsync: this, duration: widget.duration)
    ..forward().whenComplete(dismiss);
  double _drag = 0;
  bool _leaving = false;

  Future<void> dismiss() async {
    if (_leaving || !mounted) return;
    _leaving = true;
    _timer.stop();
    await _enter.reverse();
    widget.onGone();
  }

  @override
  void dispose() {
    _enter.dispose();
    _timer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final (ink, soft, icon) = widget.tone.colors(p);
    final top = MediaQuery.paddingOf(context).top + 8;

    return Positioned(
      top: top,
      left: AuraSpace.margin,
      right: AuraSpace.margin,
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final t = _enter.status == AnimationStatus.reverse
              ? Curves.easeInCubic.transform(_enter.value)
              : Curves.elasticOut.transform(_enter.value.clamp(0.0, 1.0));
          return Transform.translate(
            offset: Offset(0, (1 - t) * -110 + _drag),
            child: Transform.scale(scale: 0.92 + 0.08 * t.clamp(0.0, 1.0), child: Opacity(opacity: _enter.value.clamp(0.0, 1.0), child: child)),
          );
        },
        child: GestureDetector(
          onTap: dismiss,
          onVerticalDragUpdate: (d) => setState(() => _drag = (_drag + d.delta.dy).clamp(-120.0, 16.0)),
          onVerticalDragEnd: (d) {
            if (_drag < -30 || d.velocity.pixelsPerSecond.dy < -300) {
              dismiss();
            } else {
              setState(() => _drag = 0);
            }
          },
          child: Material(
            type: MaterialType.transparency,
            child: NeuSurface(
              radius: AuraRadius.lg,
              color: p.surfaceLow,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AuraRadius.lg),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 14, 14),
                      child: Row(
                        children: [
                          widget.leading ??
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: soft,
                                  shape: BoxShape.circle,
                                  boxShadow: [BoxShadow(color: ink.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))],
                                ),
                                child: Center(child: _PopIcon(icon: icon, color: ink)),
                              ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(widget.title, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                                if (widget.message != null)
                                  Text(widget.message!, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant), maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ),
                          ),
                          if (widget.actionLabel != null) ...[
                            const SizedBox(width: 8),
                            NeuPressable(
                              onTap: () {
                                widget.onAction?.call();
                                dismiss();
                              },
                              radius: AuraRadius.pill,
                              color: soft,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              child: Text(widget.actionLabel!, style: AuraType.labelMd.copyWith(color: ink)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Garis waktu yang menyusut.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedBuilder(
                        animation: _timer,
                        builder: (context, _) => Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: 1 - _timer.value,
                            child: Container(height: 3, color: ink.withValues(alpha: 0.55)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Ikon yang "meletup" masuk sedikit setelah toast mendarat.
class _PopIcon extends StatelessWidget {
  const _PopIcon({required this.icon, required this.color});
  final HugeIconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 700),
      curve: const Interval(0.3, 1, curve: Curves.elasticOut),
      builder: (context, t, child) => Transform.scale(scale: t, child: Transform.rotate(angle: (1 - t) * -0.6, child: child)),
      child: AuraIcon(icon, size: 20, color: color, strokeWidth: 2),
    );
  }
}

// =============================================================================
// Modal

class AuraModalAction<T> {
  const AuraModalAction(this.label, {this.value, this.primary = false, this.destructive = false});
  final String label;
  final T? value;
  final bool primary;
  final bool destructive;
}

/// Modal custom: latar di-blur perlahan, kartu naik & membesar dengan pegas,
/// ilustrasi clay opsional, tombol neumorph. Mengembalikan `value` aksi yang dipilih.
Future<T?> showAuraModal<T>(
  BuildContext context, {
  required String title,
  String? message,
  ClayKind? art,
  Widget? body,
  List<AuraModalAction<T>> actions = const [],
  bool dismissible = true,
}) {
  HapticFeedback.lightImpact();
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: dismissible,
      barrierLabel: 'Tutup',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 520),
      reverseTransitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, anim, _) => _AuraModalView<T>(anim: anim, title: title, message: message, art: art, body: body, actions: actions, dismissible: dismissible),
    ),
  );
}

class _AuraModalView<T> extends StatelessWidget {
  const _AuraModalView({
    required this.anim,
    required this.title,
    required this.message,
    required this.art,
    required this.body,
    required this.actions,
    required this.dismissible,
  });
  final Animation<double> anim;
  final String title;
  final String? message;
  final ClayKind? art;
  final Widget? body;
  final List<AuraModalAction<T>> actions;
  final bool dismissible;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        final reversing = anim.status == AnimationStatus.reverse;
        final t = reversing ? Curves.easeInCubic.transform(anim.value) : Curves.easeOutBack.transform(anim.value);
        final fade = Curves.easeOut.transform(anim.value);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onTap: dismissible ? () => Navigator.of(context).pop() : null,
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 8 * fade, sigmaY: 8 * fade),
                  child: ColoredBox(color: Colors.black.withValues(alpha: 0.22 * fade)),
                ),
              ),
            ),
            Center(
              child: Opacity(
                opacity: fade,
                child: Transform.translate(
                  offset: Offset(0, 40 * (1 - t)),
                  child: Transform.scale(scale: 0.86 + 0.14 * t, child: child),
                ),
              ),
            ),
          ],
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AuraSpace.lg),
        child: Material(
          type: MaterialType.transparency,
          child: NeuSurface(
            radius: AuraRadius.xl,
            color: p.surface,
            padding: const EdgeInsets.fromLTRB(AuraSpace.lg, AuraSpace.lg, AuraSpace.lg, AuraSpace.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (art != null) ClayArt(art!, size: 120),
                  Text(title, style: AuraType.headlineSm.copyWith(color: p.onSurface), textAlign: TextAlign.center),
                  if (message != null) ...[
                    const SizedBox(height: 6),
                    Text(message!, style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant), textAlign: TextAlign.center),
                  ],
                  if (body != null) ...[const SizedBox(height: AuraSpace.md), body!],
                  const SizedBox(height: AuraSpace.lg),
                  Row(
                    children: [
                      for (final (i, a) in actions.indexed) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(flex: a.primary || a.destructive ? 3 : 2, child: _ModalButton(action: a)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalButton<T> extends StatelessWidget {
  const _ModalButton({required this.action});
  final AuraModalAction<T> action;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final filled = action.primary || action.destructive;
    final colors = action.destructive ? [p.secondary, const Color(0xFFD9706C)] : [p.primaryContainer, p.secondaryContainer];
    return NeuPressable(
      onTap: () => Navigator.of(context).pop(action.value),
      radius: AuraRadius.pill,
      height: 50,
      pressedDepth: filled ? 0 : -0.7,
      color: filled ? colors.first : p.surfaceLow,
      child: DecoratedBox(
        decoration: filled
            ? BoxDecoration(borderRadius: BorderRadius.circular(AuraRadius.pill), gradient: LinearGradient(colors: colors))
            : const BoxDecoration(),
        child: Center(
          child: Text(
            action.label,
            style: AuraType.labelLg.copyWith(color: filled ? Colors.white : p.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// Banner

/// Banner di dalam halaman untuk kondisi yang bertahan (offline, gagal sinkron,
/// tagihan terlambat). Masuk dengan membuka tinggi + geser, bisa ditutup.
class AuraBanner extends StatelessWidget {
  const AuraBanner({
    super.key,
    required this.visible,
    required this.title,
    this.message,
    this.tone = AuraTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
  });

  final bool visible;
  final String title;
  final String? message;
  final AuraTone tone;
  final HugeIconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final (ink, soft, defaultIcon) = tone.colors(p);
    return AnimatedSize(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(position: Tween(begin: const Offset(0, -0.25), end: Offset.zero).animate(a), child: child),
        ),
        child: !visible
            ? const SizedBox(width: double.infinity, key: ValueKey('none'))
            : Padding(
                key: ValueKey(title),
                padding: const EdgeInsets.only(bottom: AuraSpace.md),
                child: NeuSurface(
                  depth: 0.7,
                  radius: AuraRadius.lg,
                  color: Color.alphaBlend(soft.withValues(alpha: p.isDark ? 0.25 : 0.55), p.surfaceLow),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AuraRadius.lg),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: 5, color: ink),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                              child: Row(
                                children: [
                                  AuraIcon(icon ?? defaultIcon, color: ink, size: 22),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(title, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                                        if (message != null) Text(message!, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                                      ],
                                    ),
                                  ),
                                  if (actionLabel != null)
                                    TextButton(
                                      onPressed: onAction,
                                      style: TextButton.styleFrom(foregroundColor: ink, textStyle: AuraType.labelMd),
                                      child: Text(actionLabel!),
                                    ),
                                  if (onDismiss != null)
                                    IconButton(
                                      onPressed: onDismiss,
                                      visualDensity: VisualDensity.compact,
                                      icon: AuraIcon(HugeIcons.strokeRoundedCancel01, size: 16, color: p.outline),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

