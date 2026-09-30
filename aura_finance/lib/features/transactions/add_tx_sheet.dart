import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/icons/category_icons.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';

Future<void> showAddTxSheet(BuildContext context, {TxEntry? existing, TxKind? kind}) {
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    sheetAnimationStyle: const AnimationStyle(
      duration: Duration(milliseconds: 520),
      reverseDuration: Duration(milliseconds: 280),
      curve: Curves.easeOutBack,
    ),
    builder: (_) => AddTxSheet(existing: existing, initialKind: kind),
  );
}

class AddTxSheet extends ConsumerStatefulWidget {
  const AddTxSheet({super.key, this.existing, this.initialKind});
  final TxEntry? existing;
  final TxKind? initialKind;

  @override
  ConsumerState<AddTxSheet> createState() => _AddTxSheetState();
}

class _AddTxSheetState extends ConsumerState<AddTxSheet> {
  late TxKind _kind = widget.existing?.kind ?? widget.initialKind ?? TxKind.expense;
  late String _digits = widget.existing == null ? '' : '${widget.existing!.amount}';
  late String? _walletId = widget.existing?.walletId;
  late String? _toWalletId = widget.existing?.toWalletId;
  late String? _categoryId = widget.existing?.categoryId;
  late DateTime _date = widget.existing?.occurredAt ?? DateTime.now();
  late final _note = TextEditingController(text: widget.existing?.note ?? '');
  int _shake = 0;
  bool _saved = false;

  int get _amount => int.tryParse(_digits) ?? 0;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _press(String key) {
    setState(() {
      if (key == 'del') {
        if (_digits.isNotEmpty) _digits = _digits.substring(0, _digits.length - 1);
      } else if (_digits.length < 12) {
        final next = (_digits + key).replaceFirst(RegExp(r'^0+'), '');
        _digits = next;
      }
    });
  }

  String? _validate() {
    if (_amount <= 0) return 'Masukkan nominal dulu';
    if (_walletId == null) return 'Pilih dompet';
    if (_kind == TxKind.transfer) {
      if (_toWalletId == null) return 'Pilih dompet tujuan';
      if (_toWalletId == _walletId) return 'Dompet tujuan harus berbeda';
    } else if (_categoryId == null) {
      return 'Pilih kategori';
    }
    return null;
  }

  Future<void> _save() async {
    final error = _validate();
    if (error != null) {
      HapticFeedback.heavyImpact();
      setState(() => _shake++);
      AuraToast.error(context, error);
      return;
    }
    final owner = ownerStamp(ref);
    final db = ref.read(dbProvider);
    final e = widget.existing;
    await db.upsertTx(TxEntriesCompanion(
      id: Value(e?.id ?? newId()),
      householdId: Value(e?.householdId ?? owner.householdId),
      createdBy: Value(e?.createdBy ?? owner.userId),
      createdAt: Value(e?.createdAt ?? DateTime.now()),
      kind: Value(_kind),
      amount: Value(_amount),
      walletId: Value(_walletId!),
      toWalletId: Value(_kind == TxKind.transfer ? _toWalletId : null),
      categoryId: Value(_kind == TxKind.transfer ? null : _categoryId),
      note: Value(_note.text.trim()),
      occurredAt: Value(_date),
      recurringRuleId: Value(e?.recurringRuleId),
      billId: Value(e?.billId),
    ));
    HapticFeedback.heavyImpact();
    setState(() => _saved = true);
    await Future<void>.delayed(const Duration(milliseconds: 650));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final tx = widget.existing!;
    final ok = await confirmDelete(
      context,
      title: 'Hapus transaksi ini?',
      message: '${Rupiah.format(tx.amount)}${tx.note.isEmpty ? '' : ' · ${tx.note}'} akan dihapus dari riwayat dan saldo dompet.',
    );
    if (!ok || !mounted) return;
    final db = ref.read(dbProvider);
    await db.softDeleteTx(tx.id);
    if (!mounted) return;
    final nav = Navigator.of(context);
    AuraToast.show(
      context,
      title: 'Transaksi dihapus',
      tone: AuraTone.warning,
      actionLabel: 'Urungkan',
      onAction: () => db.restoreTx(tx.id),
      duration: const Duration(seconds: 5),
    );
    nav.pop();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2015),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() => _date = DateTime(picked.year, picked.month, picked.day, _date.hour, _date.minute));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final wallets = ref.watch(walletBalancesProvider).value ?? const [];
    final categories = (ref.watch(categoriesProvider).value ?? const <Category>[])
        .where((c) => c.kind == (_kind == TxKind.income ? CategoryKind.income : CategoryKind.expense))
        .toList();
    _walletId ??= wallets.isEmpty ? null : wallets.first.wallet.id;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final accent = switch (_kind) {
      TxKind.income => p.tertiary,
      TxKind.expense => p.primary,
      TxKind.transfer => p.secondary,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(AuraRadius.xl)),
        ),
        child: SafeArea(
          top: false,
          child: wallets.isEmpty
              ? _NoWallet(onCreate: () {
                  Navigator.of(context).pop();
                  context.push('/wallets');
                })
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(AuraSpace.margin, 10, AuraSpace.margin, AuraSpace.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(color: p.outlineVariant, borderRadius: BorderRadius.circular(3)),
                        ),
                      ),
                      const SizedBox(height: AuraSpace.md),
                      NeuSegmented<TxKind>(
                        value: _kind,
                        options: const {TxKind.expense: 'Pengeluaran', TxKind.income: 'Pemasukan', TxKind.transfer: 'Transfer'},
                        onChanged: (k) => setState(() {
                          _kind = k;
                          _categoryId = null;
                        }),
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _AmountDisplay(digits: _digits, color: accent, shake: _shake),
                      const SizedBox(height: AuraSpace.md),
                      _WalletRow(
                        label: _kind == TxKind.transfer ? 'Dari' : 'Dompet',
                        wallets: wallets,
                        selected: _walletId,
                        onSelect: (id) => setState(() => _walletId = id),
                      ),
                      if (_kind == TxKind.transfer) ...[
                        const SizedBox(height: AuraSpace.sm),
                        _WalletRow(
                          label: 'Ke',
                          wallets: wallets.where((w) => w.wallet.id != _walletId).toList(),
                          selected: _toWalletId,
                          onSelect: (id) => setState(() => _toWalletId = id),
                        ),
                      ] else ...[
                        const SizedBox(height: AuraSpace.md),
                        _CategoryGrid(
                          categories: categories,
                          selected: _categoryId,
                          onSelect: (id) => setState(() => _categoryId = id),
                        ),
                      ],
                      const SizedBox(height: AuraSpace.md),
                      Row(
                        children: [
                          Expanded(
                            child: ShadInput(
                              controller: _note,
                              placeholder: const Text('Catatan (opsional)'),
                              leading: const AuraIcon(HugeIcons.strokeRoundedPencilEdit02, size: 18),
                            ),
                          ),
                          const SizedBox(width: AuraSpace.sm),
                          NeuPressable(
                            onTap: _pickDate,
                            radius: AuraRadius.md,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                AuraIcon(HugeIcons.strokeRoundedCalendar03, size: 18, color: accent),
                                const SizedBox(width: 6),
                                Text(DateId.relativeDay(_date), style: AuraType.labelMd.copyWith(color: p.onSurface)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AuraSpace.md),
                      _Keypad(onKey: _press),
                      const SizedBox(height: AuraSpace.md),
                      _SaveButton(saved: _saved, color: accent, onTap: _saved ? null : _save, editing: widget.existing != null),
                      if (widget.existing != null && !_saved)
                        Center(
                          child: TextButton.icon(
                            onPressed: _delete,
                            style: TextButton.styleFrom(foregroundColor: p.error, textStyle: AuraType.labelLg),
                            icon: AuraIcon(HugeIcons.strokeRoundedDelete02, size: 18, color: p.error),
                            label: const Text('Hapus transaksi'),
                          ),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  const _AmountDisplay({required this.digits, required this.color, required this.shake});
  final String digits;
  final Color color;
  final int shake;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final value = int.tryParse(digits) ?? 0;
    final text = Rupiah.digits(value);
    return TweenAnimationBuilder<double>(
      key: ValueKey(shake),
      tween: Tween(begin: shake == 0 ? 1 : 0, end: 1),
      duration: const Duration(milliseconds: 480),
      builder: (context, t, child) {
        // Getar kiri-kanan saat validasi gagal.
        final dx = math.sin(t * math.pi * 6) * 12 * (1 - t);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text('Rp', style: AuraType.headlineMd.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                children: [
                  // Setiap karakter muncul dengan pop kecil.
                  for (var i = 0; i < text.length; i++)
                    _PopChar(
                      key: ValueKey('${text.length}-$i-${text[i]}'),
                      char: text[i],
                      style: AuraType.displayLg.copyWith(color: value == 0 ? p.outlineVariant : p.onSurface),
                    ),
                  _Caret(color: color),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PopChar extends StatelessWidget {
  const _PopChar({super.key, required this.char, required this.style});
  final String char;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 10 * (1 - t)),
        child: Opacity(opacity: t.clamp(0, 1), child: child),
      ),
      child: Text(char, style: style),
    );
  }
}

class _Caret extends StatefulWidget {
  const _Caret({required this.color});
  final Color color;

  @override
  State<_Caret> createState() => _CaretState();
}

class _CaretState extends State<_Caret> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        margin: const EdgeInsets.only(left: 4),
        width: 3,
        height: 38,
        decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(2)),
      ),
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({required this.label, required this.wallets, required this.selected, required this.onSelect});
  final String label;
  final List<WalletBalance> wallets;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return SizedBox(
      height: 46,
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(label, style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant))),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: wallets.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final w = wallets[i].wallet;
                final active = w.id == selected;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  child: NeuPressable(
                    onTap: () => onSelect(w.id),
                    restDepth: active ? -0.8 : 0.8,
                    pressedDepth: -0.8,
                    radius: AuraRadius.pill,
                    color: active ? p.surfaceContainer : p.surfaceLow,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 240),
                          width: active ? 10 : 8,
                          height: active ? 10 : 8,
                          decoration: BoxDecoration(color: Color(w.color), shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          w.name,
                          style: AuraType.labelMd.copyWith(color: active ? p.onSurface : p.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryGrid extends StatelessWidget {
  const _CategoryGrid({required this.categories, required this.selected, required this.onSelect});
  final List<Category> categories;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return SizedBox(
      height: 172,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.05),
        itemCount: categories.length,
        itemBuilder: (context, i) {
          final c = categories[i];
          final active = c.id == selected;
          final tone = Color(c.color);
          return NeuPressable(
            onTap: () => onSelect(c.id),
            restDepth: active ? -0.9 : 0.9,
            pressedDepth: -0.9,
            radius: AuraRadius.md,
            color: active ? Color.alphaBlend(tone.withValues(alpha: 0.14), p.surfaceContainer) : p.surfaceLow,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedScale(
                  scale: active ? 1.15 : 1,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: AuraIcon(categoryIcon(c.icon), size: 24, color: tone, strokeWidth: active ? 2 : 1.6),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    c.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: AuraType.labelSm.copyWith(color: active ? p.onSurface : p.onSurfaceVariant, letterSpacing: 0),
                  ),
                ),
              ],
            ),
          ).staggerIn(i, stepMs: 18);
        },
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({required this.onKey});
  final ValueChanged<String> onKey;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    const keys = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '000', '0', 'del'];
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.3,
      clipBehavior: Clip.none,
      children: [
        for (final k in keys)
          NeuPressable(
            onTap: () => onKey(k),
            onLongPress: k == 'del' ? () => onKey('del') : null,
            radius: AuraRadius.md,
            pressedScale: 0.93,
            semanticLabel: k == 'del' ? 'Hapus' : k,
            child: Center(
              child: k == 'del'
                  ? CustomPaint(size: const Size(26, 20), painter: _BackspacePainter(p.onSurfaceVariant))
                  : Text(k, style: AuraType.headlineMd.copyWith(color: p.onSurface)),
            ),
          ),
      ],
    );
  }
}

class _SaveButton extends StatelessWidget {
  const _SaveButton({required this.saved, required this.color, required this.onTap, required this.editing});
  final bool saved;
  final Color color;
  final VoidCallback? onTap;
  final bool editing;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutBack,
        width: saved ? 60 : MediaQuery.sizeOf(context).width,
        height: 60,
        child: NeuPressable(
          onTap: onTap,
          radius: AuraRadius.pill,
          color: color,
          pressedDepth: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AuraRadius.pill),
              gradient: LinearGradient(colors: [color, Color.lerp(color, p.primaryContainer, 0.45)!]),
            ),
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                child: saved
                    // Centang di sini memang berarti "tersimpan".
                    ? const AuraIcon(HugeIcons.strokeRoundedTick02, key: ValueKey('ok'), color: Colors.white, size: 28, strokeWidth: 2.4)
                    : Text(
                        editing ? 'Simpan perubahan' : 'Simpan',
                        key: const ValueKey('label'),
                        style: AuraType.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoWallet extends StatelessWidget {
  const _NoWallet({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return ClayEmpty(
      kind: ClayKind.wallet,
      title: 'Belum ada dompet',
      message: 'Buat dompet dulu (tunai, rekening, atau e-wallet) supaya transaksi punya tempat.',
      action: ShadButton(onPressed: onCreate, child: const Text('Buat dompet')),
    );
  }
}

/// Ikon backspace: badan tombol dengan ujung runcing ke kiri dan tanda silang.
class _BackspacePainter extends CustomPainter {
  _BackspacePainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final body = Path()
      ..moveTo(w * 0.3, h * 0.05)
      ..lineTo(w * 0.86, h * 0.05)
      ..quadraticBezierTo(w * 0.98, h * 0.05, w * 0.98, h * 0.2)
      ..lineTo(w * 0.98, h * 0.8)
      ..quadraticBezierTo(w * 0.98, h * 0.95, w * 0.86, h * 0.95)
      ..lineTo(w * 0.3, h * 0.95)
      ..lineTo(w * 0.03, h * 0.5)
      ..close();
    canvas.drawPath(body, paint);
    final cx = w * 0.6, cy = h * 0.5, d = h * 0.2;
    canvas.drawLine(Offset(cx - d, cy - d), Offset(cx + d, cy + d), paint);
    canvas.drawLine(Offset(cx + d, cy - d), Offset(cx - d, cy + d), paint);
  }

  @override
  bool shouldRepaint(_BackspacePainter old) => old.color != color;
}
