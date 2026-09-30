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
import '../../data/local/database.dart';
import '../../data/providers.dart';
import '../../data/remote/household_service.dart';
import '../../data/remote/neon.dart';
import '../../data/sync/sync_providers.dart';
import '../../services/notifications.dart';
import '../../services/realtime.dart';

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
      final svc = ref.read(householdServiceProvider);
      await svc.saveProfile(name.isNotEmpty ? name : _email.text.split('@').first);
      // Install ulang / ganti HP: sambungkan kembali ke rumah tangga yang sudah ada di server.
      // Bila ada lebih dari satu, pengguna memilih sendiri di layar berikutnya.
      if (!_signUp) {
        final restored = await svc.restoreIfSingle();
        if (restored != null) {
          AuraToast.global(
            title: 'Data akunmu dipulihkan',
            message: '${restored.household.name} · ${restored.transactions} transaksi dimuat dari server.',
            tone: AuraTone.success,
          );
        }
      }
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
      // Kabar dari pasangan muncul sebagai notifikasi -> minta izinnya sekarang.
      await ref.read(prefsProvider).setBool('notif_asked', true);
      await ref.read(notificationsProvider).requestPermission();
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
        const _SavedHouseholds(title: 'Data di akunmu', hint: 'Pulihkan catatan yang tersimpan di server'),
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
                      'Semua data yang sudah kamu catat di perangkat ini akan ikut dipindahkan ke rumah tangga baru. '
                      'Data baru tersimpan di server (aman saat ganti HP) setelah rumah tangga dibuat.',
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

  Future<void> _removeMember(BuildContext context, WidgetRef ref, Member m) async {
    final ok = await confirmDelete(
      context,
      title: 'Keluarkan ${m.displayName}?',
      message: '${m.displayName} tidak bisa lagi melihat atau mengubah data rumah tangga ini, dan datanya dilepas dari HP-nya. '
          'Catatan yang sudah ia buat tetap tersimpan di sini. Ia bisa bergabung lagi dengan kode undangan.',
      confirmLabel: 'Keluarkan',
    );
    if (!ok) return;
    try {
      await ref.read(householdServiceProvider).removeMember(m.userId);
      HapticFeedback.mediumImpact();
      AuraToast.global(title: '${m.displayName} dikeluarkan', tone: AuraTone.warning);
    } catch (e) {
      if (context.mounted) AuraToast.error(context, _friendlyError(e));
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref, String name, List<Member> members, String? me) async {
    final others = members.where((m) => m.userId != me).toList();
    final isOwner = members.any((m) => m.userId == me && m.role == 'owner');
    final ok = await confirmDelete(
      context,
      title: others.isEmpty ? 'Hapus $name?' : 'Keluar dari $name?',
      message: others.isEmpty
          ? 'Kamu anggota terakhir. Rumah tangga ini beserta SELURUH datanya (dompet, transaksi, target, tagihan) '
              'akan dihapus permanen dari server dan tidak bisa dipulihkan.'
          : 'Data rumah tangga tetap tersimpan untuk ${others.map((m) => m.displayName).join(', ')}, '
              'tetapi dilepas dari HP ini dan kamu tidak bisa melihatnya lagi.'
              '${isOwner ? ' Kepemilikan dipindahkan ke ${others.first.displayName}.' : ''}',
      confirmLabel: others.isEmpty ? 'Hapus permanen' : 'Keluar',
    );
    if (!ok) return;
    try {
      final deleted = await ref.read(householdServiceProvider).leave();
      HapticFeedback.heavyImpact();
      AuraToast.global(
        title: deleted ? '$name dihapus' : 'Kamu keluar dari $name',
        message: 'Buat rumah tangga baru, gabung dengan kode, atau pulihkan yang lain dari akunmu.',
        tone: AuraTone.warning,
      );
    } catch (e) {
      if (context.mounted) AuraToast.error(context, _friendlyError(e));
    }
  }

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
        const _SavedHouseholds(
          title: 'Rumah tangga lain di akunmu',
          hint: 'Data lama setelah install ulang ada di sini — pindah untuk memulihkannya',
        ),
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
                  if (isOwner && m.userId != me) ...[
                    const SizedBox(width: 8),
                    NeuIconButton(
                      HugeIcons.strokeRoundedUserRemove01,
                      size: 36,
                      color: p.error,
                      label: 'Keluarkan ${m.displayName}',
                      onTap: () => _removeMember(context, ref, m),
                    ),
                  ],
                ],
              ),
            ).staggerIn(i),
          ),
        const SizedBox(height: AuraSpace.lg),
        const SectionHeader('Yang bisa dilakukan bersama'),
        const SizedBox(height: AuraSpace.sm + 4),
        const _SharingGuide(),
        const SizedBox(height: AuraSpace.lg),
        const SectionHeader('Notifikasi'),
        const SizedBox(height: AuraSpace.sm + 4),
        const _NotificationCard(),
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
          label: 'Keluar dari rumah tangga',
          destructive: true,
          onPressed: () => _leave(context, ref, h.value?.name ?? 'rumah tangga ini', members, me),
        ),
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

/// Status notifikasi di luar aplikasi: izin Android + pendaftaran push (FCM),
/// dengan tombol untuk mengaktifkan dan mengirim notifikasi uji.
class _NotificationCard extends ConsumerStatefulWidget {
  const _NotificationCard();

  @override
  ConsumerState<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends ConsumerState<_NotificationCard> with WidgetsBindingObserver {
  bool? _enabled;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Kembali dari pengaturan Android -> perbarui status izin.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final on = await ref.read(notificationsProvider).enabled();
    if (mounted) setState(() => _enabled = on);
  }

  Future<void> _enable() async {
    final granted = await ref.read(notificationsProvider).requestPermission();
    // Izin yang sudah pernah ditolak tidak memunculkan dialog lagi -> buka pengaturan.
    if (!granted) await ref.read(realtimeProvider.notifier).openNotificationSettings();
    await _refresh();
    final uid = ref.read(authUserProvider).value?.id;
    if (granted && uid != null) await ref.read(realtimeProvider.notifier).registerPush(uid);
  }

  Future<void> _test() async {
    setState(() => _sending = true);
    final ok = await ref.read(realtimeProvider.notifier).sendTestPush();
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      AuraToast.show(
        context,
        title: 'Keluar dari aplikasi sekarang',
        message: 'Notifikasi uji dikirim dalam 6 detik. Kalau tidak muncul, cek pengaturan baterai HP.',
        duration: const Duration(seconds: 6),
      );
    } else {
      AuraToast.error(context, 'Gagal mengirim notifikasi uji', message: 'Periksa koneksi internet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final push = ref.watch(pushStatusProvider);
    final enabled = _enabled;

    Widget row(bool? ok, String title, String detail) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AuraIcon(
                ok == null
                    ? HugeIcons.strokeRoundedLoading03
                    : ok
                        ? HugeIcons.strokeRoundedCheckmarkCircle02
                        : HugeIcons.strokeRoundedAlert02,
                size: 20,
                color: ok == null ? p.outline : (ok ? p.tertiary : p.error),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                    Text(detail, style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
        );

    return NeuSurface(
      radius: AuraRadius.lg,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          row(
            enabled,
            enabled == false ? 'Izin notifikasi mati' : 'Izin notifikasi',
            enabled == false
                ? 'Kabar dari pasangan hanya terlihat saat aplikasi dibuka.'
                : 'Aura boleh menampilkan notifikasi di luar aplikasi.',
          ),
          row(
            push.error != null ? false : (push.registered ? true : null),
            'Push dari pasangan',
            push.error != null
                ? 'Belum terdaftar: ${push.error}'
                : push.registered
                    ? 'HP ini terdaftar untuk menerima kabar saat aplikasi tertutup.'
                    : 'Sedang mendaftarkan HP ini…',
          ),
          if (!push.registered && enabled != false)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.link(
                onPressed: () {
                  final uid = ref.read(authUserProvider).value?.id;
                  if (uid == null) return;
                  ref.read(pushStatusProvider.notifier).set(const PushStatus());
                  ref.read(realtimeProvider.notifier).registerPush(uid);
                },
                child: const Text('Daftarkan ulang HP ini'),
              ),
            ),
          if (enabled == false)
            PrimaryAction(label: 'Aktifkan notifikasi', onPressed: _enable)
          else
            ShadButton.outline(
              onPressed: _sending ? null : _test,
              leading: const AuraIcon(HugeIcons.strokeRoundedNotification03, size: 18),
              child: Text(_sending ? 'Mengirim…' : 'Kirim notifikasi uji'),
            ),
          const SizedBox(height: 10),
          Text(
            'HP Xiaomi/Redmi/POCO, Oppo, Vivo: aktifkan "Mulai otomatis" dan atur baterai Aura ke '
            '"Tanpa batasan", supaya notifikasi tetap masuk saat aplikasi ditutup.',
            style: AuraType.bodySm.copyWith(color: p.outline),
          ),
          if (enabled != false)
            Align(
              alignment: Alignment.centerLeft,
              child: ShadButton.link(
                onPressed: () => ref.read(realtimeProvider.notifier).openNotificationSettings(),
                child: const Text('Buka pengaturan notifikasi'),
              ),
            ),
        ],
      ),
    );
  }
}

/// Rumah tangga milik akun ini yang tersimpan di server. Setelah install ulang atau
/// ganti HP, di sinilah data lama dipulihkan; juga untuk pindah dari rumah tangga
/// yang tidak sengaja dibuat baru.
class _SavedHouseholds extends ConsumerStatefulWidget {
  const _SavedHouseholds({required this.title, required this.hint});
  final String title;
  final String hint;

  @override
  ConsumerState<_SavedHouseholds> createState() => _SavedHouseholdsState();
}

class _SavedHouseholdsState extends ConsumerState<_SavedHouseholds> {
  String? _busy;

  Future<void> _restore(Household h) async {
    final current = ref.read(householdIdProvider);
    if (current != null) {
      final ok = await showAuraModal<bool>(
        context,
        title: 'Pindah ke ${h.name}?',
        message: 'Perangkat ini akan menampilkan data ${h.name}. Data rumah tangga yang sekarang tetap aman di server '
            'dan bisa dipulihkan lagi dari sini.',
        actions: const [AuraModalAction('Batal', value: false), AuraModalAction('Pindah', value: true, primary: true)],
      );
      if (ok != true || !mounted) return;
    }
    setState(() => _busy = h.id);
    try {
      await ref.read(householdServiceProvider).restore(h);
      HapticFeedback.heavyImpact();
      ref.invalidate(currentHouseholdProvider);
      AuraToast.global(title: 'Data ${h.name} dipulihkan', message: 'Semua catatan dari server sudah dimuat.', tone: AuraTone.success);
    } catch (e) {
      if (mounted) AuraToast.error(context, _friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final current = ref.watch(householdIdProvider);
    final list = (ref.watch(myHouseholdsProvider).value ?? const <HouseholdSummary>[])
        .where((s) => s.household.id != current)
        .toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: AuraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(widget.title, subtitle: widget.hint),
          const SizedBox(height: AuraSpace.sm + 4),
          for (final (i, s) in list.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: NeuSurface(
                radius: AuraRadius.lg,
                padding: const EdgeInsets.all(AuraSpace.md),
                child: Row(
                  children: [
                    const CategoryBadge(icon: 'home', color: 0xFFFE64A3, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.household.name, style: AuraType.labelLg.copyWith(color: p.onSurface)),
                          Text(
                            '${s.transactions} transaksi · ${s.role == 'owner' ? 'pemilik' : 'anggota'}',
                            style: AuraType.bodySm.copyWith(color: p.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    ShadButton(
                      size: ShadButtonSize.sm,
                      onPressed: _busy != null ? null : () => _restore(s.household),
                      child: Text(_busy == s.household.id ? 'Memuat…' : (current == null ? 'Pulihkan' : 'Pindah')),
                    ),
                  ],
                ),
              ).staggerIn(i),
            ),
        ],
      ),
    );
  }
}
