import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:postgrest/postgrest.dart';

import '../../core/icons/category_icons.dart';
import '../../core/widgets/feedback.dart';
import '../../core/illustrations/avatars.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/date_id.dart';
import '../../core/widgets/aura_page.dart';
import '../../core/widgets/form_sheet.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/providers.dart';
import '../../data/remote/household_service.dart';
import '../../data/remote/neon.dart';
import '../../data/sync/sync_providers.dart';

class HouseholdPage extends ConsumerWidget {
  const HouseholdPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final hid = ref.watch(householdIdProvider);

    final Widget body;
    if (!Neon.enabled) {
      body = const ClayEmpty(
        kind: ClayKind.duo,
        size: 180,
        title: 'Sinkronisasi belum diatur',
        message: 'Aplikasi ini dibangun tanpa alamat Neon, jadi data hanya tersimpan di perangkat ini. '
            'Lihat README bagian "Neon" untuk mengaktifkan mode bersama.',
      );
    } else if (user == null) {
      body = const _AuthForm();
    } else if (hid == null) {
      body = const _CreateOrJoin();
    } else {
      body = const _HouseholdInfo();
    }

    return AuraPage(
      title: 'Rumah Tangga',
      subtitle: 'Kelola keuangan bersama',
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin),
          sliver: SliverToBoxAdapter(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 380),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(a), child: c),
              ),
              child: KeyedSubtree(key: ValueKey(body.runtimeType), child: body),
            ),
          ),
        ),
      ],
    );
  }
}

String _friendlyError(Object e) {
  if (e is NeonAuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('invalid email or password') || m.contains('invalid_email_or_password')) return 'Email atau kata sandi salah';
    if (m.contains('already exists') || m.contains('user_already_exists')) return 'Email sudah terdaftar — silakan masuk';
    if (m.contains('not verified') || m.contains('verif')) return 'Cek email untuk verifikasi akun dulu';
    if (m.contains('password') && m.contains('short')) return 'Kata sandi minimal 8 karakter';
    return e.message;
  }
  if (e is PostgrestException) return e.message;
  final s = e.toString();
  if (s.contains('SocketException') || s.contains('host lookup')) return 'Tidak ada koneksi internet';
  return 'Terjadi kesalahan. Coba lagi.';
}

class _AuthForm extends ConsumerStatefulWidget {
  const _AuthForm();

  @override
  ConsumerState<_AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends ConsumerState<_AuthForm> {
  bool _signUp = false;
  bool _busy = false;
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _busy = true);
    final auth = Neon.auth;
    final name = ref.read(displayNameProvider);
    try {
      if (_signUp) {
        await auth.signUp(email: _email.text.trim(), password: _password.text, name: name);
      } else {
        await auth.signIn(email: _email.text.trim(), password: _password.text);
      }
      // Profil dibuat/diperbarui dari aplikasi (Neon tidak punya trigger auth.users).
      await ref.read(householdServiceProvider).saveProfile(name.isNotEmpty ? name : _email.text.split('@').first);
    } on NeonAuthException catch (e) {
      if (mounted) {
        AuraToast.error(context, _friendlyError(e));
        if (e.status == 200) setState(() => _signUp = false);
      }
    } catch (e) {
      if (mounted) AuraToast.error(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: ClayArt(ClayKind.duo, size: 170)),
        Text(_signUp ? 'Buat akun' : 'Masuk untuk sinkron', style: AuraType.headlineMd.copyWith(color: p.onSurface), textAlign: TextAlign.center),
        const SizedBox(height: 4),
        Text(
          'Akun diperlukan agar data tersimpan di cloud dan bisa dibagikan dengan pasangan. Data lokalmu ikut terbawa.',
          style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AuraSpace.lg),
        ShadInput(
          controller: _email,
          placeholder: const Text('Email'),
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.email],
          leading: const AuraIcon(HugeIcons.strokeRoundedMail01, size: 18),
        ),
        const SizedBox(height: AuraSpace.sm + 4),
        ShadInput(
          controller: _password,
          placeholder: const Text('Kata sandi'),
          obscureText: true,
          autofillHints: [_signUp ? AutofillHints.newPassword : AutofillHints.password],
          leading: const AuraIcon(HugeIcons.strokeRoundedLockKey, size: 18),
        ),
        PrimaryAction(label: _busy ? 'Sebentar…' : (_signUp ? 'Daftar' : 'Masuk'), onPressed: _busy ? null : _submit),
        const SizedBox(height: AuraSpace.md),
        Center(
          child: GestureDetector(
            onTap: () => setState(() => _signUp = !_signUp),
            child: Text.rich(
              TextSpan(
                text: _signUp ? 'Sudah punya akun? ' : 'Belum punya akun? ',
                children: [TextSpan(text: _signUp ? 'Masuk' : 'Daftar', style: TextStyle(color: p.primary, fontWeight: FontWeight.w700))],
              ),
              style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
            ),
          ),
        ),
      ],
    );
  }
}

class _CreateOrJoin extends ConsumerStatefulWidget {
  const _CreateOrJoin();

  @override
  ConsumerState<_CreateOrJoin> createState() => _CreateOrJoinState();
}

class _CreateOrJoinState extends ConsumerState<_CreateOrJoin> {
  bool _join = false;
  bool _busy = false;
  final _name = TextEditingController(text: 'Keluarga Kita');
  String _code = '';

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      final svc = ref.read(householdServiceProvider);
      final h = _join ? await svc.join(_code) : await svc.create(_name.text.trim().isEmpty ? 'Keluarga Kita' : _name.text.trim());
      HapticFeedback.heavyImpact();
      if (mounted) AuraToast.success(context, _join ? 'Bergabung dengan ${h.name}' : '${h.name} dibuat');
      ref.invalidate(currentHouseholdProvider);
    } catch (e) {
      if (mounted) AuraToast.error(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Center(child: ClayArt(ClayKind.house, size: 160)),
        const SizedBox(height: AuraSpace.sm),
        NeuSegmented<bool>(
          value: _join,
          options: const {false: 'Buat baru', true: 'Gabung dengan kode'},
          onChanged: (v) => setState(() => _join = v),
        ),
        const SizedBox(height: AuraSpace.lg),
        AnimatedSize(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
          child: _join
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Masukkan 6 karakter kode dari pasanganmu.', style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant)),
                    const SizedBox(height: AuraSpace.md),
                    Center(
                      child: ShadInputOTP(
                        maxLength: 6,
                        keyboardType: TextInputType.visiblePassword,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
                          const _UpperCase(),
                        ],
                        onChanged: (v) => setState(() => _code = v),
                        children: const [
                          ShadInputOTPGroup(children: [ShadInputOTPSlot(), ShadInputOTPSlot(), ShadInputOTPSlot()]),
                          Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('–')),
                          ShadInputOTPGroup(children: [ShadInputOTPSlot(), ShadInputOTPSlot(), ShadInputOTPSlot()]),
                        ],
                      ),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Semua data yang sudah kamu catat di perangkat ini akan ikut dipindahkan ke rumah tangga baru.',
                      style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
                    ),
                    const FieldLabel('Nama rumah tangga'),
                    ShadInput(controller: _name, placeholder: const Text('mis. Rumah Sarah & Dimas')),
                  ],
                ),
        ),
        PrimaryAction(
          label: _busy ? 'Sebentar…' : (_join ? 'Gabung' : 'Buat rumah tangga'),
          onPressed: _busy || (_join && _code.length < 6) ? null : _go,
        ),
        const SizedBox(height: AuraSpace.md),
        ShadButton.ghost(onPressed: () => ref.read(householdServiceProvider).signOut(), child: const Text('Keluar akun')),
      ],
    );
  }
}

class _UpperCase extends TextInputFormatter {
  const _UpperCase();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}

class _HouseholdInfo extends ConsumerWidget {
  const _HouseholdInfo();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = context.aura;
    final h = ref.watch(currentHouseholdProvider);
    final members = ref.watch(membersProvider).value ?? const [];
    final sync = ref.watch(syncControllerProvider);
    final me = ref.watch(authUserProvider).value?.id;
    final isOwner = members.any((m) => m.userId == me && m.role == 'owner');
    final code = h.value?.inviteCode;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NeuSurface(
          radius: AuraRadius.xl,
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Column(
            children: [
              Text(h.value?.name ?? '…', style: AuraType.headlineMd.copyWith(color: p.onSurface)),
              const SizedBox(height: AuraSpace.md),
              Text('Kode undangan', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
              const SizedBox(height: AuraSpace.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final ch in (code ?? '······').split(''))
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      child: NeuSurface(
                        depth: -0.9,
                        radius: 12,
                        width: 40,
                        height: 48,
                        color: p.surfaceContainer,
                        child: Center(child: Text(ch, style: AuraType.headlineMd.copyWith(color: p.primary))),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AuraSpace.md),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ShadButton.outline(
                    size: ShadButtonSize.sm,
                    onPressed: code == null
                        ? null
                        : () {
                            Clipboard.setData(ClipboardData(text: code));
                            HapticFeedback.lightImpact();
                            AuraToast.info(context, 'Kode disalin');
                          },
                    leading: const AuraIcon(HugeIcons.strokeRoundedCopy01, size: 16),
                    child: const Text('Salin'),
                  ),
                  const SizedBox(width: 8),
                  ShadButton(
                    size: ShadButtonSize.sm,
                    onPressed: code == null
                        ? null
                        : () => SharePlus.instance.share(ShareParams(
                              text: 'Yuk kelola keuangan bareng di Aura. Masuk ke Profil → Rumah Tangga → Gabung, lalu masukkan kode: $code',
                            )),
                    leading: const AuraIcon(HugeIcons.strokeRoundedUserAdd01, size: 16, color: Colors.white),
                    child: const Text('Undang'),
                  ),
                ],
              ),
              if (isOwner)
                ShadButton.link(
                  onPressed: () async {
                    await ref.read(householdServiceProvider).regenerateCode();
                    ref.invalidate(currentHouseholdProvider);
                  },
                  child: const Text('Buat kode baru'),
                ),
            ],
          ),
        ),
        const SizedBox(height: AuraSpace.lg),
        const SectionHeader('Anggota'),
        const SizedBox(height: AuraSpace.sm + 4),
        for (final (i, m) in members.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: NeuSurface(
              radius: AuraRadius.md,
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  AuraAvatar(avatarKey: m.avatar, name: m.displayName, fallbackColor: Color(m.color), size: 40),
                  const SizedBox(width: 12),
                  Expanded(child: Text(m.userId == me ? '${m.displayName} (kamu)' : m.displayName, style: AuraType.labelLg.copyWith(color: p.onSurface))),
                  Text(m.role == 'owner' ? 'Pemilik' : 'Anggota', style: AuraType.labelSm.copyWith(color: p.outline)),
                ],
              ),
            ).staggerIn(i),
          ),
        const SizedBox(height: AuraSpace.lg),
        const SectionHeader('Yang bisa dilakukan bersama'),
        const SizedBox(height: AuraSpace.sm + 4),
        const _SharingGuide(),
        const SizedBox(height: AuraSpace.lg),
        NeuSurface(
          depth: -1,
          radius: AuraRadius.lg,
          color: p.surfaceContainer,
          padding: const EdgeInsets.all(AuraSpace.md),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      switch (sync.status) {
                        SyncStatus.syncing => 'Menyinkronkan…',
                        SyncStatus.offline => 'Offline — perubahan disimpan lokal',
                        SyncStatus.error => 'Sinkron gagal',
                        SyncStatus.idle => sync.pending > 0 ? '${sync.pending} perubahan menunggu' : 'Semua tersinkron',
                      },
                      style: AuraType.labelLg.copyWith(color: sync.status == SyncStatus.error ? p.error : p.onSurface),
                    ),
                    if (sync.lastSync != null)
                      Text('Terakhir ${DateId.time(sync.lastSync!)}', style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
              ),
              NeuIconButton(
                HugeIcons.strokeRoundedRefresh,
                label: 'Sinkron sekarang',
                onTap: sync.status == SyncStatus.syncing ? null : () => ref.read(syncControllerProvider.notifier).syncNow(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AuraSpace.lg),
        PrimaryAction(
          label: 'Keluar akun',
          destructive: true,
          onPressed: () async {
            final ok = await confirmDelete(
              context,
              title: 'Keluar dari akun?',
              message: 'Data tetap tersimpan di perangkat ini, tetapi tidak lagi tersinkron sampai kamu masuk lagi.',
              confirmLabel: 'Keluar',
            );
            if (!ok) return;
            await ref.read(householdServiceProvider).signOut();
          },
        ),
      ],
    );
  }
}

/// Ringkasan apa yang dibagikan & apa yang tetap pribadi di rumah tangga.
class _SharingGuide extends StatelessWidget {
  const _SharingGuide();

  static const _shared = [
    (HugeIcons.strokeRoundedWallet01, 'Dompet bersama', 'Saldo & semua transaksinya terlihat kalian berdua, lengkap dengan siapa yang mencatat.'),
    (HugeIcons.strokeRoundedPiggyBank, 'Target bersama', 'Menabung berdua — lihat kontribusi masing-masing dan dapat kabar setiap ada setoran.'),
    (HugeIcons.strokeRoundedTarget02, 'Budget bersama', 'Batas belanja dari dompet bersama; peringatan 80% & 100% dikirim ke semua anggota.'),
    (HugeIcons.strokeRoundedInvoice03, 'Tagihan & transaksi berulang', 'Siapa pun bisa menandai lunas; anggota lain langsung diberi tahu.'),
    (HugeIcons.strokeRoundedTag01, 'Kategori', 'Satu daftar kategori untuk seluruh rumah tangga.'),
  ];

  static const _private = [
    (HugeIcons.strokeRoundedLockKey, 'Dompet, target & budget pribadi', 'Matikan "bersama" saat membuat. Hanya kamu yang melihat isinya.'),
    (HugeIcons.strokeRoundedView, 'Beranda: Semua / Bersama / Pribadiku', 'Pilih cakupan di Beranda untuk melihat keuangan pribadi atau bersama saja.'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    Widget row((HugeIconData, String, String) r, Color tone) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              NeuSurface(
                depth: -0.8,
                radius: 12,
                width: 38,
                height: 38,
                color: p.surfaceContainer,
                child: Center(child: AuraIcon(r.$1, size: 19, color: tone)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.$2, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                    Text(r.$3, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );
    return NeuSurface(
      radius: AuraRadius.lg,
      padding: const EdgeInsets.fromLTRB(AuraSpace.md, AuraSpace.md, AuraSpace.md, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final r in _shared) row(r, p.primary),
          Divider(color: p.outlineVariant.withValues(alpha: 0.5), height: 8),
          const SizedBox(height: 10),
          Text('Tetap bisa sendiri-sendiri', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 10),
          for (final r in _private) row(r, p.tertiary),
        ],
      ),
    );
  }
}
