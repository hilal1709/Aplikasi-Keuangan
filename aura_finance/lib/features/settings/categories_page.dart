import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import '../../core/icons/category_icons.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/owner.dart';
import '../../data/providers.dart';

class CategoriesPage extends ConsumerStatefulWidget {
  const CategoriesPage({super.key});

  @override
  ConsumerState<CategoriesPage> createState() => _CategoriesPageState();
}

class _CategoriesPageState extends ConsumerState<CategoriesPage> {
  CategoryKind _kind = CategoryKind.expense;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final cats = (ref.watch(categoriesProvider).value ?? const <Category>[]).where((c) => c.kind == _kind).toList();
    return AuraPage(
      title: 'Kategori',
      actions: [
        NeuIconButton(HugeIcons.strokeRoundedAdd01, label: 'Tambah kategori', color: p.primary, onTap: () => _form(context, kind: _kind)),
      ],
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverList.list(
            children: [
              NeuSegmented<CategoryKind>(
                value: _kind,
                options: const {CategoryKind.expense: 'Pengeluaran', CategoryKind.income: 'Pemasukan'},
                onChanged: (k) => setState(() => _kind = k),
              ),
              const SizedBox(height: AuraSpace.lg),
              GridView.builder(
                key: ValueKey(_kind),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                clipBehavior: Clip.none,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, mainAxisSpacing: 14, crossAxisSpacing: 14, childAspectRatio: 0.95),
                itemCount: cats.length,
                itemBuilder: (context, i) {
                  final c = cats[i];
                  return NeuPressable(
                    onTap: () => _form(context, kind: _kind, existing: c),
                    radius: AuraRadius.lg,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CategoryBadge(icon: c.icon, color: c.color, size: 46),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AuraType.labelMd.copyWith(color: p.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ).staggerIn(i, stepMs: 25);
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _form(BuildContext context, {required CategoryKind kind, Category? existing}) {
    return showFormSheet<void>(context, title: existing == null ? 'Kategori baru' : 'Ubah kategori', builder: (_) => _CategoryForm(kind: kind, existing: existing));
  }
}

class _CategoryForm extends ConsumerStatefulWidget {
  const _CategoryForm({required this.kind, this.existing});
  final CategoryKind kind;
  final Category? existing;

  @override
  ConsumerState<_CategoryForm> createState() => _CategoryFormState();
}

class _CategoryFormState extends ConsumerState<_CategoryForm> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late String _icon = widget.existing?.icon ?? 'other';
  late int _color = widget.existing?.color ?? categoryTones.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save({bool archive = false}) async {
    if (_name.text.trim().isEmpty) {
      AuraToast.error(context, 'Nama kategori belum diisi');
      return;
    }
    final e = widget.existing;
    final owner = ownerStamp(ref);
    await ref.read(dbProvider).upsertCategory(CategoriesCompanion(
          id: Value(e?.id ?? newId()),
          householdId: Value(e?.householdId ?? owner.householdId),
          createdBy: Value(e?.createdBy ?? owner.userId),
          createdAt: Value(e?.createdAt ?? DateTime.now()),
          name: Value(_name.text.trim()),
          kind: Value(widget.kind),
          icon: Value(_icon),
          color: Value(_color),
          sortOrder: Value(e?.sortOrder ?? 999),
          archived: Value(archive),
          seedKey: Value(e?.seedKey),
        ));
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    final e = widget.existing!;
    final db = ref.read(dbProvider);
    final n = await db.countTxForCategory(e.id);
    if (!mounted) return;
    final ok = await confirmDelete(
      context,
      title: 'Hapus kategori ${e.name}?',
      message: n == 0
          ? 'Budget untuk kategori ini juga akan dihapus.'
          : '$n transaksi tetap ada tetapi menjadi "Tanpa kategori". Budget kategori ini ikut dihapus.',
    );
    if (!ok) return;
    await db.softDeleteCategory(e.id);
    if (mounted) {
      AuraToast.success(context, 'Kategori dihapus');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: CategoryBadge(icon: _icon, color: _color, size: 72)),
        const FieldLabel('Nama'),
        ShadInput(controller: _name, placeholder: const Text('mis. Skincare'), textCapitalization: TextCapitalization.sentences),
        const FieldLabel('Ikon'),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (i, key) in categoryIcons.keys.indexed)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _icon = key);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: key == _icon ? Color(_color).withValues(alpha: 0.18) : p.surfaceContainer,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: key == _icon ? Color(_color) : Colors.transparent, width: 1.5),
                  ),
                  child: Center(child: AuraIcon(categoryIcon(key), size: 20, color: key == _icon ? Color(_color) : p.onSurfaceVariant)),
                ),
              ).popIn(delayMs: 180 + math.min(i, 24) * 18),
          ],
        ),
        const FieldLabel('Warna'),
        ToneSwatches(value: _color, onChanged: (c) => setState(() => _color = c)),
        PrimaryAction(label: 'Simpan', onPressed: _save),
        if (widget.existing != null) PrimaryAction(label: 'Hapus kategori', destructive: true, onPressed: _delete),
      ],
    );
  }
}
