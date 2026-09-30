import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../app/router.dart';
import '../../core/illustrations/avatars.dart';
import '../../core/illustrations/clay.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/utils/rupiah.dart';
import '../../core/widgets/neu_surface.dart';
import '../../core/widgets/primitives.dart';
import '../../data/local/database.dart';
import '../../data/providers.dart';

class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _Slide {
  const _Slide(this.kind, this.title, this.body);
  final ClayKind kind;
  final String title;
  final String body;
}

const _slides = [
  _Slide(ClayKind.jar, 'Catat tanpa ribet', 'Tanpa sambungan ke bank. Kamu yang pegang kendali — catat dalam tiga ketukan, bahkan saat offline.'),
  _Slide(ClayKind.duo, 'Kelola berdua', 'Undang pasangan atau keluarga. Dompet bersama tersinkron otomatis, dompet pribadi tetap milikmu.'),
  _Slide(ClayKind.chart, 'Lihat polanya', 'Budget, target tabungan, dan skor kesehatan finansial membantu kalian mengambil keputusan.'),
];

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  final _pager = PageController();
  double _page = 0;
  final _name = TextEditingController();
  final _walletName = TextEditingController(text: 'Tunai');
  String _balanceDigits = '';
  WalletKind _walletKind = WalletKind.cash;

  @override
  void initState() {
    super.initState();
    _pager.addListener(() => setState(() => _page = _pager.page ?? 0));
  }

  @override
  void dispose() {
    _pager.dispose();
    _name.dispose();
    _walletName.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final db = ref.read(dbProvider);
    if (_name.text.trim().isNotEmpty) ref.read(displayNameProvider.notifier).set(_name.text);
    if (ref.read(avatarKeyProvider) == null) {
      ref.read(avatarKeyProvider.notifier).set(avatarSpecs[DateTime.now().millisecond % 10].key);
    }
    await db.upsertWallet(WalletsCompanion.insert(
      id: newId(),
      name: _walletName.text.trim().isEmpty ? 'Tunai' : _walletName.text.trim(),
      kind: _walletKind,
      color: 0xFFFE64A3,
      initialBalance: Value(int.tryParse(_balanceDigits) ?? 0),
    ));
    await ref.read(prefsProvider).setBool(onboardedKey, true);
    HapticFeedback.heavyImpact();
    if (mounted) context.go('/');
  }

  void _next() {
    FocusScope.of(context).unfocus();
    _pager.nextPage(duration: const Duration(milliseconds: 600), curve: Curves.easeInOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final total = _slides.length + 1;
    final isSetup = _page > _slides.length - 0.5;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AuraSpace.margin, AuraSpace.md, AuraSpace.margin, 0),
              child: Row(
                children: [
                  Image.asset('assets/brand/logo_mark.png', width: 34, height: 34),
                  const SizedBox(width: AuraSpace.xs),
                  Text('Aura', style: AuraType.headlineSm.copyWith(color: p.primary, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  if (!isSetup)
                    GestureDetector(
                      onTap: () => _pager.animateToPage(_slides.length, duration: const Duration(milliseconds: 700), curve: Curves.easeInOutCubic),
                      child: Text('Lewati', style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pager,
                itemCount: total,
                itemBuilder: (context, i) {
                  // Parallax: ilustrasi bergerak lebih lambat dari teks.
                  final delta = i - _page;
                  if (i == _slides.length) return _setup(context, delta);
                  final s = _slides[i];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AuraSpace.xl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Transform.translate(
                          offset: Offset(delta * 120, 0),
                          child: Transform.scale(
                            scale: 1 - delta.abs() * 0.2,
                            child: NeuSurface(
                              circle: true,
                              width: 260,
                              height: 260,
                              child: Center(child: ClayArt(s.kind, size: 220)),
                            ),
                          ),
                        ),
                        const SizedBox(height: AuraSpace.xl + 8),
                        Opacity(
                          opacity: (1 - delta.abs() * 1.6).clamp(0, 1),
                          child: Column(
                            children: [
                              Text(s.title, style: AuraType.headlineLg.copyWith(color: p.onSurface), textAlign: TextAlign.center),
                              const SizedBox(height: AuraSpace.sm + 4),
                              Text(s.body, style: AuraType.bodyLg.copyWith(color: p.onSurfaceVariant, fontWeight: FontWeight.w400), textAlign: TextAlign.center),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AuraSpace.margin, 0, AuraSpace.margin, AuraSpace.lg),
              child: Row(
                children: [
                  // Indikator halaman: titik aktif memanjang.
                  for (var i = 0; i < total; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeOutBack,
                      margin: const EdgeInsets.only(right: 6),
                      width: (_page - i).abs() < 0.5 ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: (_page - i).abs() < 0.5 ? p.primaryContainer : p.outlineVariant,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  const Spacer(),
                  NeuPressable(
                    onTap: isSetup ? _finish : _next,
                    radius: AuraRadius.pill,
                    color: p.primaryContainer,
                    pressedDepth: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      height: 56,
                      width: isSetup ? 160 : 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AuraRadius.pill),
                        gradient: LinearGradient(colors: [p.primaryContainer, p.secondaryContainer]),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 220),
                          child: isSetup
                              ? Text('Mulai', key: const ValueKey('go'), style: AuraType.bodyLg.copyWith(color: Colors.white, fontWeight: FontWeight.w700))
                              : const AuraIcon(HugeIcons.strokeRoundedArrowRight01, key: ValueKey('next'), color: Colors.white, strokeWidth: 2.2),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _setup(BuildContext context, double delta) {
    final p = context.aura;
    return Opacity(
      opacity: (1 - delta.abs() * 1.4).clamp(0, 1),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: AuraSpace.margin, vertical: AuraSpace.lg),
        children: [
          const Center(child: ClayArt(ClayKind.wallet, size: 130)),
          const SizedBox(height: AuraSpace.sm),
          Text('Kenalan dulu', style: AuraType.headlineLg.copyWith(color: p.onSurface), textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(
            'Nama dan dompet pertamamu. Semua bisa diubah nanti.',
            style: AuraType.bodyMd.copyWith(color: p.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AuraSpace.lg),
          Text('Nama panggilan', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 6),
          ShadInput(controller: _name, placeholder: const Text('mis. Sarah'), textCapitalization: TextCapitalization.words),
          const SizedBox(height: AuraSpace.md),
          Text('Dompet pertama', style: AuraType.labelMd.copyWith(color: p.onSurfaceVariant)),
          const SizedBox(height: 6),
          NeuSegmented<WalletKind>(
            value: _walletKind,
            options: const {WalletKind.cash: 'Tunai', WalletKind.bank: 'Rekening', WalletKind.ewallet: 'E-wallet'},
            onChanged: (k) => setState(() {
              _walletKind = k;
              _walletName.text = switch (k) {
                WalletKind.cash => 'Tunai',
                WalletKind.bank => 'Rekening',
                WalletKind.ewallet => 'E-wallet',
                WalletKind.other => 'Dompet',
              };
            }),
          ),
          const SizedBox(height: AuraSpace.sm + 4),
          ShadInput(controller: _walletName, placeholder: const Text('Nama dompet')),
          const SizedBox(height: AuraSpace.sm + 4),
          ShadInput(
            placeholder: const Text('Saldo saat ini'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            leading: Text('Rp', style: AuraType.labelLg.copyWith(color: p.onSurfaceVariant)),
            onChanged: (v) => setState(() => _balanceDigits = v),
          ),
          if (_balanceDigits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(Rupiah.format(int.tryParse(_balanceDigits) ?? 0), style: AuraType.bodySm.copyWith(color: p.primary)),
            ),
        ],
      ),
    );
  }
}
