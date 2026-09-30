import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:home_widget/home_widget.dart';
import 'package:hugeicons/hugeicons.dart';

import '../core/icons/category_icons.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/neu_surface.dart';
import '../core/widgets/primitives.dart';
import '../core/utils/date_id.dart';
import '../core/utils/rupiah.dart';
import '../data/providers.dart';
import '../data/sync/sync_providers.dart';
import '../features/insights/insights_providers.dart';
import '../features/transactions/add_tx_sheet.dart';
import '../services/home_widget_sync.dart';
import '../services/notifications.dart';
import '../core/illustrations/avatars.dart';
import '../core/widgets/feedback.dart';
import '../services/realtime.dart';
import '../services/recurring_runner.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  bool _sheetOpen = false;
  StreamSubscription<Uri?>? _widgetClicks;
  StreamSubscription<PartnerEvent>? _partner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _housekeeping();
      final launched = await HomeWidget.initiallyLaunchedFromHomeWidget();
      if (launched?.host == 'add' && mounted) _openAdd();
    });
    _widgetClicks = HomeWidget.widgetClicked.listen((uri) {
      if (uri?.host == 'add' && mounted && !_sheetOpen) _openAdd();
    });
    // Catatan pasangan yang masuk saat aplikasi terbuka -> toast dengan avatarnya.
    _partner = ref.read(realtimeProvider.notifier).events.listen((e) {
      if (!mounted) return;
      final m = (ref.read(membersProvider).value ?? const []).where((x) => x.userId == e.by).firstOrNull;
      AuraToast.show(
        context,
        title: e.title,
        message: e.body.isEmpty ? null : e.body,
        leading: AuraAvatar(avatarKey: m?.avatar, name: m?.displayName ?? '', size: 40),
        tone: e.kind == 'budget' ? AuraTone.warning : AuraTone.info,
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetClicks?.cancel();
    _partner?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _housekeeping();
    if (state == AppLifecycleState.paused) HomeWidgetSync.push(ref.read(dbProvider)).ignore();
  }

  /// Tugas rutin saat app dibuka/kembali: catat transaksi berulang yang jatuh tempo,
  /// jadwalkan ulang pengingat tagihan, dan perbarui widget layar utama.
  Future<void> _housekeeping() async {
    final db = ref.read(dbProvider);
    // Kabar dari pasangan butuh izin notifikasi (Android 13+). Diminta sekali saat
    // sudah tergabung rumah tangga; setelahnya bisa diatur dari halaman Rumah Tangga.
    final prefs = ref.read(prefsProvider);
    if (ref.read(householdIdProvider) != null && !(prefs.getBool('notif_asked') ?? false)) {
      await prefs.setBool('notif_asked', true);
      await ref.read(notificationsProvider).requestPermission();
    }
    try {
      await runDueRecurring(db);
      await ref.read(notificationsProvider).rescheduleBills();
      await HomeWidgetSync.push(db);
    } catch (_) {
      // Tugas latar tidak boleh mengganggu pemakaian.
    }
  }

  Future<void> _openAdd() async {
    setState(() => _sheetOpen = true);
    HapticFeedback.mediumImpact();
    await showAddTxSheet(context);
    if (mounted) setState(() => _sheetOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    AuraToast.attach(context);
    ref.watch(syncControllerProvider);
    ref.watch(realtimeProvider);
    // Peringatan budget 80% / 100% — hanya jika dipicu catatan dari HP ini,
    // anggota lain diberi tahu lewat push supaya tidak dobel.
    ref.listen(budgetUsageProvider(DateId.monthStart(DateTime.now())), (prev, next) async {
      final last = ref.read(dbProvider).lastLocalTxWrite;
      if (last == null || DateTime.now().difference(last) > const Duration(seconds: 15)) return;
      final notif = ref.read(notificationsProvider);
      final before = {for (final u in prev ?? const <BudgetUsage>[]) u.budget.id: u.ratio};
      for (final u in next) {
        final t = u.ratio >= 1 ? 100 : (u.ratio >= 0.8 ? 80 : 0);
        if (t == 0 || u.category == null) continue;
        // Hanya bila ambang baru saja terlewati oleh catatan ini, supaya pasangan yang
        // mencatat belakangan tidak mengirim peringatan yang sama untuk kedua kalinya.
        final was = before[u.budget.id];
        if (was == null || was >= t / 100) continue;
        final fresh = await notif.budgetAlert(budgetId: u.budget.id, category: u.category!.name, threshold: t, spent: u.spent, limit: u.budget.limitAmount);
        // Budget pribadi cukup diingatkan di HP ini; budget bersama juga dikabarkan ke pasangan.
        if (fresh && u.budget.isShared) {
          ref.read(realtimeProvider.notifier).notify(
                kind: 'budget',
                title: t >= 100 ? 'Budget ${u.category!.name} terlampaui' : 'Budget ${u.category!.name} sudah $t%',
                body: '${Rupiah.format(u.spent)} dari ${Rupiah.format(u.budget.limitAmount)} terpakai bulan ini',
              );
        }
      }
    });
    final p = context.aura;
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      extendBody: true,
      body: Stack(
        children: [
          _TabTransition(index: widget.shell.currentIndex, child: widget.shell),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: top + 20,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [p.surface, p.surface.withValues(alpha: 0.92), p.surface.withValues(alpha: 0)],
                    stops: [0, top / (top + 20), 1],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _NavBar(
        index: widget.shell.currentIndex,
        fabOpen: _sheetOpen,
        onTap: (i) {
          if (i == widget.shell.currentIndex) return;
          HapticFeedback.selectionClick();
          widget.shell.goBranch(i, initialLocation: i == widget.shell.currentIndex);
        },
        onFab: _openAdd,
      ),
    );
  }
}

/// Pergantian tab: konten baru naik sedikit + fade + membesar halus.
/// Anak tidak diberi key baru, jadi state tiap tab (IndexedStack) tetap utuh.
class _TabTransition extends StatefulWidget {
  const _TabTransition({required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  State<_TabTransition> createState() => _TabTransitionState();
}

class _TabTransitionState extends State<_TabTransition> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 460), value: 1);
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutExpo);

  @override
  void didUpdateWidget(_TabTransition old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index && !Motion.reduced(context)) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (context, child) {
          final t = _a.value;
          return Opacity(
            opacity: 0.2 + 0.8 * t,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - t)),
              child: Transform.scale(scale: 0.985 + 0.015 * t, child: child),
            ),
          );
        },
      );
}

class _NavItem {
  const _NavItem(this.icon, this.label);
  final HugeIconData icon;
  final String label;
}

const _items = [
  _NavItem(HugeIcons.strokeRoundedHome01, 'Beranda'),
  _NavItem(HugeIcons.strokeRoundedAnalytics01, 'Insight'),
  _NavItem(HugeIcons.strokeRoundedPiggyBank, 'Target'),
  _NavItem(HugeIcons.strokeRoundedUserGroup, 'Profil'),
];

class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onTap, required this.onFab, required this.fabOpen});
  final int index;
  final ValueChanged<int> onTap;
  final VoidCallback onFab;
  final bool fabOpen;

  @override
  Widget build(BuildContext context) {
    final p = context.aura;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(AuraSpace.margin, 0, AuraSpace.margin, bottom + AuraSpace.md),
      child: SizedBox(
        height: 84,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            NeuSurface(
              height: 72,
              radius: AuraRadius.pill,
              color: p.surface.withValues(alpha: 0.97),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: LayoutBuilder(
                builder: (context, box) {
                  // 5 slot: 2 kiri, FAB tengah, 2 kanan.
                  final slot = box.maxWidth / 5;
                  final visual = index < 2 ? index : index + 1;
                  return Stack(
                    children: [
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 460),
                        curve: Curves.easeOutBack,
                        left: slot * visual + (slot - 56) / 2,
                        top: 8,
                        width: 56,
                        height: 56,
                        child: NeuSurface(depth: -0.9, circle: true, color: p.surfaceContainer),
                      ),
                      Row(
                        children: [
                          for (var i = 0; i < 2; i++) _slot(context, i),
                          const Expanded(child: SizedBox()),
                          for (var i = 2; i < 4; i++) _slot(context, i),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
            Positioned(
              top: -6,
              child: NeuPressable(
                onTap: onFab,
                circle: true,
                width: 62,
                height: 62,
                pressedDepth: 0,
                pressedScale: 0.9,
                semanticLabel: 'Catat transaksi',
                color: p.primaryContainer,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.bottomLeft,
                      end: Alignment.topRight,
                      colors: [p.primaryContainer, p.secondaryContainer],
                    ),
                    boxShadow: [BoxShadow(color: p.primaryContainer.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))],
                  ),
                  child: Center(
                    child: AnimatedRotation(
                      turns: fabOpen ? 0.125 : 0,
                      duration: const Duration(milliseconds: 380),
                      curve: Curves.easeOutBack,
                      child: const AuraIcon(HugeIcons.strokeRoundedAdd01, size: 28, color: Colors.white, strokeWidth: 2.2),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _slot(BuildContext context, int i) {
    final p = context.aura;
    final active = i == index;
    return Expanded(
      child: Semantics(
        selected: active,
        button: true,
        label: _items[i].label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onTap(i),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: active ? 1.08 : 1,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutBack,
                child: AuraIcon(_items[i].icon, size: 22, color: active ? p.primary : p.onSurfaceVariant, strokeWidth: active ? 2 : 1.6),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: active
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(_items[i].label, style: AuraType.labelSm.copyWith(color: p.primary)),
                      )
                    : const SizedBox(width: 0),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
