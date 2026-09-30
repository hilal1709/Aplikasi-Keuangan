import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../icons/category_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'feedback.dart';
import 'lottie.dart';
import 'neu_surface.dart';
import 'primitives.dart';

/// Bottom sheet formulir bergaya Aura (dipakai dompet, target, budget, tagihan, dst).
Future<T?> showFormSheet<T>(BuildContext context, {required String title, required WidgetBuilder builder}) {
  return showModalBottomSheet<T>(
    context: context,
    // Di atas nav bar: sheet dibuka di navigator akar, bukan navigator tab.
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 480),
      reverseDuration: Duration(milliseconds: 260),
      curve: Curves.easeOutBack,
    ),
    builder: (context) {
      final p = context.aura;
      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: FormShake(
          child: Container(
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(AuraRadius.xl)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(AuraSpace.margin, 10, AuraSpace.margin, AuraSpace.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 5,
                        decoration: BoxDecoration(color: p.outlineVariant, borderRadius: BorderRadius.circular(3)),
                      ),
                    ),
                    const SizedBox(height: AuraSpace.md),
                    SplitReveal(title, delayMs: 140, stepMs: 22, style: AuraType.headlineMd.copyWith(color: p.onSurface)),
                    const SizedBox(height: AuraSpace.md),
                    _SheetCascade(
                      child: _FocusSpotlight(child: Builder(builder: builder)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6, top: AuraSpace.sm + 4, left: 2),
    child: Text(text, style: AuraType.labelMd.copyWith(color: context.aura.onSurfaceVariant)),
  ).cascadeIn(context);
}

/// Input nominal rupiah: hanya angka, dengan pratinjau format di bawahnya.
class AmountField extends StatefulWidget {
  const AmountField({super.key, required this.initial, required this.onChanged, this.placeholder = '0', this.allowZero = true});
  final int initial;
  final ValueChanged<int> onChanged;
  final String placeholder;
  final bool allowZero;

  @override
  State<AmountField> createState() => _AmountFieldState();
}

class _AmountFieldState extends State<AmountField> {
  late final _c = TextEditingController(text: widget.initial == 0 ? '' : '${widget.initial}');

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final v = int.tryParse(_c.text) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ShadInput(
          controller: _c,
          placeholder: Text(widget.placeholder),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(13)],
          leading: Text('Rp', style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant)),
          onChanged: (s) {
            setState(() {});
            widget.onChanged(int.tryParse(s) ?? 0);
          },
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          child: v == 0
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: MoneyText(
                    v,
                    duration: const Duration(milliseconds: 450),
                    style: AuraType.bodySm.copyWith(color: p.primary),
                  ),
                ),
        ),
      ],
    ).cascadeIn(context);
  }
}

/// Pilihan warna: bulatan yang membesar & mendapat cincin saat terpilih.
class ToneSwatches extends StatelessWidget {
  const ToneSwatches({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final (i, c) in categoryTones.indexed)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onChanged(c);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              width: 36,
              height: 36,
              padding: EdgeInsets.all(c == value ? 4 : 0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c == value ? Color(c) : Colors.transparent, width: 2),
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(c),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: p.shadowDark, blurRadius: 6, offset: const Offset(2, 2))],
                ),
              ),
            ),
          ).popIn(delayMs: 200 + ((i - (categoryTones.length - 1) / 2).abs() * 45).round()),
      ],
    ).cascadeIn(context);
  }
}

/// Tombol aksi utama bergradien di bagian bawah formulir.
class PrimaryAction extends StatefulWidget {
  const PrimaryAction({super.key, required this.label, required this.onPressed, this.destructive = false});
  final String label;

  /// Bila mengembalikan `Future`, tombol menampilkan animasi memuat sampai selesai.
  final FutureOr<void> Function()? onPressed;
  final bool destructive;

  @override
  State<PrimaryAction> createState() => _PrimaryActionState();
}

class _PrimaryActionState extends State<PrimaryAction> with SingleTickerProviderStateMixin {
  // Kilau menyapu tombol utama setiap ~3,4 dtk; di antara sapuan tidak ada frame yang digambar.
  late final AnimationController _shine = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
  Timer? _timer;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !widget.destructive && !Motion.reduced(context);
    if (animate && _timer == null) {
      _timer = Timer.periodic(const Duration(milliseconds: 3400), (_) {
        if (mounted && !_busy) _shine.forward(from: 0);
      });
    } else if (!animate) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shine.dispose();
    super.dispose();
  }

  Future<void> _tap() async {
    final r = widget.onPressed?.call();
    if (r is! Future || widget.destructive) return;
    setState(() => _busy = true);
    try {
      await r;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final enabled = widget.onPressed != null && !_busy;
    final label = AnimatedSwitcher(
      duration: Motion.base,
      switchInCurve: Curves.easeOutBack,
      transitionBuilder: (child, a) => FadeTransition(
        opacity: a,
        child: ScaleTransition(scale: a, child: child),
      ),
      child: _busy
          ? const AuraLoader(key: ValueKey('busy'), width: 56, color: Colors.white, accent: Colors.white70)
          : Text(
              widget.label,
              key: ValueKey(widget.label),
              style: widget.destructive
                  ? AuraType.labelLg.copyWith(color: p.error)
                  : AuraType.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
            ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: AuraSpace.lg),
      child: AnimatedScale(
        duration: Motion.base,
        curve: Curves.easeOutBack,
        scale: widget.onPressed != null ? 1 : 0.97,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: widget.onPressed != null ? 1 : 0.55,
          child: widget.destructive
              // Aksi berisiko: pil timbul netral dengan teks merah, tidak menonjol.
              ? NeuPressable(
                  onTap: enabled ? _tap : null,
                  height: 54,
                  radius: AuraRadius.pill,
                  child: Center(child: label),
                )
              : NeuPressable(
                  onTap: enabled ? _tap : null,
                  height: 56,
                  radius: AuraRadius.pill,
                  pressedDepth: 0,
                  color: p.primaryContainer,
                  child: AnimatedBuilder(
                    animation: _shine,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AuraRadius.pill),
                        gradient: LinearGradient(colors: [p.primaryContainer, p.secondaryContainer]),
                        boxShadow: [BoxShadow(color: p.primaryContainer.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                      ),
                      child: Center(child: label),
                    ),
                    builder: (context, child) {
                      if (!_shine.isAnimating || _busy) return child!;
                      return ShimmerSweep(t: Curves.easeInOutSine.transform(_shine.value), color: Colors.white.withValues(alpha: 0.35), radius: AuraRadius.pill, child: child!);
                    },
                  ),
                ),
        ),
      ),
    );
  }
}

/// Konfirmasi hapus dengan modal custom.
Future<bool> confirmDelete(BuildContext context, {required String title, required String message, String confirmLabel = 'Hapus'}) async {
  final ok = await showAuraModal<bool>(
    context,
    title: title,
    message: message,
    actions: [const AuraModalAction('Batal', value: false), AuraModalAction(confirmLabel, value: true, destructive: true)],
  );
  return ok ?? false;
}

// Dipakai beberapa halaman untuk label ikon kecil.
Widget iconLabel(BuildContext context, HugeIconData icon, String text) {
  final p = context.aura;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AuraIcon(icon, size: 14, color: p.outline),
      const SizedBox(width: 4),
      Text(text, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
    ],
  );
}

/// Sakelar Bersama/Pribadi untuk dompet, target & budget.
/// Data yang sudah dibagikan tidak bisa ditarik jadi pribadi lagi (salinannya sudah
/// ada di HP anggota lain), jadi sakelar dikunci pada kondisi itu.
class ShareToggle extends StatelessWidget {
  const ShareToggle({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.sharedHint = 'Terlihat & bisa diubah semua anggota rumah tangga',
    this.privateHint = 'Hanya terlihat olehmu',
    this.locked = false,
  });
  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;
  final String sharedHint;
  final String privateHint;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.only(top: AuraSpace.md),
      child: Row(
        children: [
          AnimatedSwitcher(
            duration: Motion.base,
            transitionBuilder: (child, a) => RotationTransition(
              turns: Tween(begin: 0.6, end: 1.0).animate(CurvedAnimation(parent: a, curve: Curves.easeOutBack)),
              child: ScaleTransition(scale: a, child: child),
            ),
            child: AuraIcon(
              value ? HugeIcons.strokeRoundedUserGroup : HugeIcons.strokeRoundedLockKey,
              key: ValueKey(value),
              size: 20,
              color: p.primary,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                AnimatedSwitcher(
                  duration: Motion.fast,
                  layoutBuilder: (current, previous) => Stack(alignment: Alignment.centerLeft, children: [...previous, ?current]),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(
                      position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a),
                      child: child,
                    ),
                  ),
                  child: Text(
                    locked ? 'Sudah dibagikan — tidak bisa dijadikan pribadi lagi' : (value ? sharedHint : privateHint),
                    key: ValueKey('$locked$value'),
                    style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          ShadSwitch(value: value, onChanged: locked ? null : onChanged),
        ],
      ),
    ).cascadeIn(context);
  }
}

/// Label kecil "Bersama" (dengan avatar anggota) atau "Pribadi".
class ShareBadge extends StatelessWidget {
  const ShareBadge({super.key, required this.shared, this.avatars = const []});
  final bool shared;
  final List<Widget> avatars;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Container(
      padding: EdgeInsets.fromLTRB(avatars.isEmpty ? 8 : 3, 3, 8, 3),
      decoration: BoxDecoration(color: shared ? p.primaryFixed : p.surfaceHigh, borderRadius: BorderRadius.circular(AuraRadius.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (shared && avatars.isNotEmpty)
            SizedBox(
              width: 18.0 + (avatars.length - 1) * 12,
              height: 18,
              child: Stack(
                children: [for (final (i, a) in avatars.indexed) Positioned(left: i * 12.0, child: a)],
              ),
            )
          else
            AuraIcon(
              shared ? HugeIcons.strokeRoundedUserGroup : HugeIcons.strokeRoundedLockKey,
              size: 13,
              color: shared ? p.onPrimaryFixed : p.onSurfaceVariant,
            ),
          const SizedBox(width: 5),
          Text(
            shared ? 'Bersama' : 'Pribadi',
            style: AuraType.labelSm.copyWith(color: shared ? p.onPrimaryFixed : p.onSurfaceVariant, letterSpacing: 0),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// Animasi isi sheet

/// Membagikan urutan kemunculan komponen di dalam satu sheet, sehingga label,
/// input & tombol mengalir masuk berurutan tanpa tiap form mengatur indeks sendiri.
class _SheetCascade extends InheritedWidget {
  _SheetCascade({required super.child});
  final _next = <int>[0];

  int take() => _next[0]++;

  @override
  bool updateShouldNotify(_SheetCascade old) => false;
}

extension SheetCascadeX on Widget {
  /// Di dalam [showFormSheet]: muncul bertingkat sesuai urutan dibangun. Di luar sheet: apa adanya.
  Widget cascadeIn(BuildContext context) {
    final c = context.getInheritedWidgetOfExactType<_SheetCascade>();
    return c == null ? this : staggerIn(c.take(), stepMs: 40, baseMs: 160);
  }
}

/// Membungkus isi sheet: menggoyang sheet saat validasi gagal ([FormShake.of]).
class FormShake extends StatefulWidget {
  const FormShake({super.key, required this.child});
  final Widget child;

  /// Goyangkan sheet terdekat (dipanggil otomatis oleh `AuraToast.error`).
  static void shake(BuildContext context) => context.findAncestorStateOfType<_FormShakeState>()?.shake();

  @override
  State<FormShake> createState() => _FormShakeState();
}

class _FormShakeState extends State<FormShake> {
  int _n = 0;

  void shake() {
    HapticFeedback.heavyImpact();
    setState(() => _n++);
  }

  @override
  Widget build(BuildContext context) => ShakeX(trigger: _n, child: widget.child);
}

/// Cincin sorot yang "meluncur" dari satu input ke input berikutnya saat fokus berpindah.
class _FocusSpotlight extends StatefulWidget {
  const _FocusSpotlight({required this.child});
  final Widget child;

  @override
  State<_FocusSpotlight> createState() => _FocusSpotlightState();
}

class _FocusSpotlightState extends State<_FocusSpotlight> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // Posisi input diukur tiap frame hanya sebentar setelah ada perubahan (fokus, keyboard,
  // gulir, ukuran) — tidak terus-menerus, supaya layar bisa diam & hemat baterai.
  late final Ticker _ticker = createTicker(_tick);
  Duration _until = Duration.zero;
  Duration _elapsed = Duration.zero;
  Rect? _rect;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocus);
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() => _kick();

  void _onFocus() {
    if (_focusedInput() != null) {
      _kick();
    } else {
      _ticker.stop();
      if (_rect != null && mounted) setState(() => _rect = null);
    }
  }

  void _kick() {
    if (!mounted || _focusedInput() == null) return;
    if (_ticker.isActive) {
      _until = _elapsed + const Duration(milliseconds: 700);
    } else {
      _until = const Duration(milliseconds: 700);
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    _measure();
    if (elapsed >= _until) _ticker.stop();
  }

  /// Elemen [ShadInput] yang sedang fokus di dalam sheet ini, bila ada.
  Element? _focusedInput() {
    final fc = FocusManager.instance.primaryFocus?.context;
    if (fc == null || !mounted) return null;
    Element? input;
    var mine = false;
    (fc as Element).visitAncestorElements((e) {
      if (input == null && e.widget is ShadInput) input = e;
      if (e.widget == widget) {
        mine = true;
        return false;
      }
      return true;
    });
    return mine ? input : null;
  }

  void _measure() {
    final input = _focusedInput()?.findRenderObject();
    final me = context.findRenderObject();
    if (input is! RenderBox || me is! RenderBox || !input.attached || !input.hasSize) return;
    final r = input.localToGlobal(Offset.zero, ancestor: me) & input.size;
    if (r != _rect) setState(() => _rect = r);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final r = _rect;
    final reduced = Motion.reduced(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NotificationListener<Notification>(
          onNotification: (n) {
            if (n is ScrollNotification || n is SizeChangedLayoutNotification) _kick();
            return false;
          },
          child: widget.child,
        ),
        if (r != null)
          AnimatedPositioned(
            duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
            curve: Curves.easeOutBack,
            left: r.left - 3,
            top: r.top - 3,
            width: r.width + 6,
            height: r.height + 6,
            child: IgnorePointer(
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: reduced ? 1 : 0, end: 1),
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutCubic,
                builder: (context, t, _) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AuraRadius.md),
                    border: Border.all(color: p.primary.withValues(alpha: 0.55 * t), width: 1.6),
                    boxShadow: [
                      BoxShadow(
                        color: p.primaryContainer.withValues(alpha: 0.28 * t),
                        blurRadius: 16 * t,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
