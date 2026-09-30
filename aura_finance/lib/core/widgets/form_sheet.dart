import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../icons/category_icons.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/rupiah.dart';
import 'feedback.dart';
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
                  Text(title, style: AuraType.headlineMd.copyWith(color: p.onSurface)),
                  const SizedBox(height: AuraSpace.md),
                  builder(context),
                ],
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
      );
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
                  child: Text(Rupiah.format(v), style: AuraType.bodySm.copyWith(color: p.primary)),
                ),
        ),
      ],
    );
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
        for (final c in categoryTones)
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
          ),
      ],
    );
  }
}

/// Tombol aksi utama bergradien di bagian bawah formulir.
class PrimaryAction extends StatelessWidget {
  const PrimaryAction({super.key, required this.label, required this.onPressed, this.destructive = false});
  final String label;
  final VoidCallback? onPressed;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final enabled = onPressed != null;
    return Padding(
      padding: const EdgeInsets.only(top: AuraSpace.lg),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: enabled ? 1 : 0.55,
        child: destructive
            // Aksi berisiko: pil timbul netral dengan teks merah, tidak menonjol.
            ? NeuPressable(
                onTap: onPressed,
                height: 54,
                radius: AuraRadius.pill,
                child: Center(child: Text(label, style: AuraType.labelLg.copyWith(color: p.error))),
              )
            : NeuPressable(
                onTap: onPressed,
                height: 56,
                radius: AuraRadius.pill,
                pressedDepth: 0,
                color: p.primaryContainer,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AuraRadius.pill),
                    gradient: LinearGradient(colors: [p.primaryContainer, p.secondaryContainer]),
                    boxShadow: [BoxShadow(color: p.primaryContainer.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: Text(label, style: AuraType.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
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
    actions: [
      const AuraModalAction('Batal', value: false),
      AuraModalAction(confirmLabel, value: true, destructive: true),
    ],
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
