import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../core/widgets/feedback.dart';
import 'package:flutter/services.dart';

import '../../core/icons/category_icons.dart';
import '../../core/illustrations/avatars.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/providers.dart';
import '../../data/remote/household_service.dart';
import '../../data/remote/neon.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/app_lock.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final top = MediaQuery.paddingOf(context).top;
    final name = ref.watch(displayNameProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final household = ref.watch(currentHouseholdProvider).value;
    final user = ref.watch(authUserProvider).value;
    final mode = ref.watch(themeModeProvider);
    final lock = ref.watch(appLockEnabledProvider);
    final hidden = ref.watch(hideBalanceProvider);
    final avatar = ref.watch(avatarKeyProvider);

    var i = 0;
    return ListView(
      physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
      padding: EdgeInsets.fromLTRB(AuraSpace.margin, top + AuraSpace.md, AuraSpace.margin, 140),
      children: [
        SplitReveal('Profil', delayMs: 100, style: AuraType.headlineLg.copyWith(color: p.onSurface)).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        NeuPressable(
          onTap: () => _editName(context, ref, name),
          radius: AuraRadius.xl,
          pressedScale: 0.985,
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => showAvatarPicker(context, ref),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Hero(tag: 'my-avatar', child: AuraAvatar(avatarKey: avatar, name: name, size: 64, fallbackColor: p.primaryContainer)),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: NeuSurface(
                        circle: true,
                        width: 26,
                        height: 26,
                        child: Center(child: AuraIcon(HugeIcons.strokeRoundedPencilEdit02, size: 13, color: p.primary)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AuraSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name.isEmpty ? 'Tambahkan nama' : name, style: AuraType.headlineSm.copyWith(color: p.onSurface)),
                    Text(user?.email ?? 'Mode lokal — data hanya di perangkat ini', style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
              ),
              AuraIcon(HugeIcons.strokeRoundedPencilEdit02, size: 18, color: p.outline),
            ],
          ),
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        NeuPressable(
          onTap: () => context.push('/household'),
          radius: AuraRadius.xl,
          pressedScale: 0.985,
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rumah tangga', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
                        Text(
                          household?.name ?? (Neon.enabled ? 'Belum terhubung' : 'Sinkronisasi belum diatur'),
                          style: AuraType.headlineSm.copyWith(color: p.onSurface),
                        ),
                      ],
                    ),
                  ),
                  AuraIcon(HugeIcons.strokeRoundedArrowRight01, color: p.outline),
                ],
              ),
              const SizedBox(height: AuraSpace.md),
              if (members.isEmpty)
                Text(
                  'Undang pasangan atau keluarga untuk mencatat bersama.',
                  style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
                )
              else
                SizedBox(
                  height: 44,
                  child: Stack(
                    children: [
                      for (final (j, m) in members.indexed)
                        Positioned(left: j * 30.0, child: AuraAvatar(avatarKey: m.avatar, name: m.displayName, fallbackColor: Color(m.color), size: 44, ring: p.surfaceLow)),
                    ],
                  ),
                ),
            ],
          ),
        ).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        _Group(children: [
          _Row(icon: HugeIcons.strokeRoundedWallet01, label: 'Dompet', onTap: () => context.push('/wallets')),
          _Row(icon: HugeIcons.strokeRoundedTag01, label: 'Kategori', onTap: () => context.push('/categories')),
          _Row(icon: HugeIcons.strokeRoundedTarget02, label: 'Budget', onTap: () => context.push('/budgets')),
          _Row(icon: HugeIcons.strokeRoundedRepeat, label: 'Transaksi berulang', onTap: () => context.push('/recurring')),
          _Row(icon: HugeIcons.strokeRoundedInvoice03, label: 'Tagihan', onTap: () => context.push('/bills')),
        ]).staggerIn(i++),
        const SizedBox(height: AuraSpace.lg),
        _Group(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              children: [
                AuraIcon(mode == ThemeMode.dark ? HugeIcons.strokeRoundedMoon02 : HugeIcons.strokeRoundedSun03, color: p.primary),
                const SizedBox(width: 12),
                Expanded(child: Text('Tema', style: AuraType.labelLg.copyWith(color: p.onSurface))),
                SizedBox(
                  width: 190,
                  child: NeuSegmented<ThemeMode>(
                    value: mode,
                    options: const {ThemeMode.system: 'Auto', ThemeMode.light: 'Terang', ThemeMode.dark: 'Gelap'},
                    onChanged: (m) => ref.read(themeModeProvider.notifier).set(m),
                  ),
                ),
              ],
            ),
          ),
          _SwitchRow(
            icon: HugeIcons.strokeRoundedFingerPrint,
            label: 'Kunci dengan sidik jari',
            value: lock,
            onChanged: (v) async {
              final ok = await ref.read(appLockEnabledProvider.notifier).set(v);
              if (!ok && context.mounted) {
                AuraToast.error(context, 'Perangkat tidak mendukung atau verifikasi gagal');
              }
            },
          ),
          _SwitchRow(
            icon: HugeIcons.strokeRoundedViewOff,
            label: 'Sembunyikan saldo',
            value: hidden,
            onChanged: (_) => ref.read(hideBalanceProvider.notifier).toggle(),
          ),
        ]).staggerIn(i++),
        const SizedBox(height: AuraSpace.xl),
        Center(child: Text('Aura • dicatat manual, disimpan dengan aman', style: AuraType.bodySm.copyWith(color: p.outline))),
      ],
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) {
    final c = TextEditingController(text: current);
    return showFormSheet<void>(
      context,
      title: 'Nama panggilan',
      builder: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShadInput(controller: c, placeholder: const Text('Nama'), autofocus: true, textCapitalization: TextCapitalization.words),
          PrimaryAction(
            label: 'Simpan',
            onPressed: () async {
              ref.read(displayNameProvider.notifier).set(c.text);
              if (ref.read(authUserProvider).value != null) {
                await ref.read(householdServiceProvider).saveProfile(c.text.trim());
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  const _Group({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return NeuSurface(
      radius: AuraRadius.xl,
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        children: [
          for (final (i, c) in children.indexed) ...[
            c,
            if (i < children.length - 1) Divider(height: 1, indent: 50, endIndent: 14, color: p.outlineVariant.withValues(alpha: 0.4)),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.onTap});
  final HugeIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AuraRadius.md),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Row(
          children: [
            AuraIcon(icon, color: p.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: AuraType.labelLg.copyWith(color: p.onSurface))),
            AuraIcon(HugeIcons.strokeRoundedArrowRight01, size: 18, color: p.outline),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.label, required this.value, required this.onChanged});
  final HugeIconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          AuraIcon(icon, color: p.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: AuraType.labelLg.copyWith(color: p.onSurface))),
          ShadSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// Pemilih avatar ilustrasi: kisi 4 kolom, pilihan membesar dengan pegas
/// dan bergoyang kecil; pratinjau besar di atas ikut berganti.
Future<void> showAvatarPicker(BuildContext context, WidgetRef ref) {
  return showFormSheet<void>(context, title: 'Pilih avatar', builder: (_) => const _AvatarPicker());
}

class _AvatarPicker extends ConsumerStatefulWidget {
  const _AvatarPicker();

  @override
  ConsumerState<_AvatarPicker> createState() => _AvatarPickerState();
}

class _AvatarPickerState extends ConsumerState<_AvatarPicker> {
  late String _selected = ref.read(avatarKeyProvider) ?? avatarSpecs.first.key;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    ref.read(avatarKeyProvider.notifier).set(_selected);
    try {
      if (ref.read(authUserProvider).value != null) {
        await ref.read(householdServiceProvider).saveProfile(ref.read(displayNameProvider), avatar: _selected);
      }
    } catch (_) {
      // Tersimpan lokal; profil di server diperbarui saat simpan berikutnya.
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final name = ref.watch(displayNameProvider);
    final spec = avatarSpec(_selected)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            transitionBuilder: (c, a) => ScaleTransition(
              scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
              child: RotationTransition(turns: Tween(begin: -0.04, end: 0.0).animate(a), child: c),
            ),
            child: AuraAvatar(key: ValueKey(_selected), avatarKey: _selected, name: name, size: 112),
          ),
        ),
        const SizedBox(height: 8),
        Center(child: Text(spec.label, style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant))),
        const SizedBox(height: AuraSpace.md),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 14,
          crossAxisSpacing: 14,
          clipBehavior: Clip.none,
          children: [
            for (final (i, a) in avatarSpecs.indexed)
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() => _selected = a.key);
                },
                child: AnimatedScale(
                  scale: a.key == _selected ? 1.08 : 0.92,
                  duration: const Duration(milliseconds: 320),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: a.key == _selected ? p.primaryContainer : Colors.transparent, width: 2.5),
                    ),
                    child: AuraAvatar(avatarKey: a.key, size: 64),
                  ),
                ),
              ).staggerIn(i, stepMs: 25),
          ],
        ),
        PrimaryAction(label: _saving ? 'Menyimpan…' : 'Pakai avatar ini', onPressed: _saving ? null : _save),
      ],
    );
  }
}
