import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/rupiah.dart';
import '../../services/realtime.dart';
import '../local/database.dart';
import '../providers.dart';
import '../remote/neon.dart';
import 'sync_engine.dart';

/// Pengguna Neon Auth yang sedang login (null jika mode lokal / belum login).
final authUserProvider = StreamProvider<NeonUser?>((ref) async* {
  if (!Neon.enabled) {
    yield null;
    return;
  }
  yield Neon.auth.currentUser;
  yield* Neon.auth.onUserChanged;
});

final syncEngineProvider = Provider<SyncEngine?>((ref) {
  if (!Neon.enabled) return null;
  return SyncEngine(ref.watch(dbProvider), ref.watch(prefsProvider));
});

enum SyncStatus { idle, syncing, offline, error }

@immutable
class SyncState {
  const SyncState({this.enabled = false, this.status = SyncStatus.idle, this.pending = 0, this.lastSync, this.error});
  final bool enabled;
  final SyncStatus status;
  final int pending;
  final DateTime? lastSync;
  final String? error;

  SyncState copyWith({bool? enabled, SyncStatus? status, int? pending, DateTime? lastSync, String? error}) => SyncState(
        enabled: enabled ?? this.enabled,
        status: status ?? this.status,
        pending: pending ?? this.pending,
        lastSync: lastSync ?? this.lastSync,
        error: error,
      );
}

/// Mengatur kapan sinkronisasi berjalan: saat dibuka, saat koneksi kembali,
/// saat ada perubahan lokal (ditunda 2 detik), dan berkala selama aplikasi terbuka.
/// Neon tidak punya realtime, jadi perubahan dari pasangan ditarik lewat polling
/// (tiap 30 detik saat aplikasi di layar) dan setiap kali aplikasi dibuka kembali.
class SyncController extends Notifier<SyncState> {
  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;
  bool _again = false;

  @override
  SyncState build() {
    final engine = ref.watch(syncEngineProvider);
    final user = ref.watch(authUserProvider).value;
    final hid = ref.watch(householdIdProvider);
    final enabled = engine != null && user != null && hid != null;

    ref.onDispose(() {
      _debounce?.cancel();
      _periodic?.cancel();
    });

    if (!enabled) return const SyncState();

    final pendingSub = engine.watchPending().listen((n) {
      state = state.copyWith(pending: n);
      if (n > 0) _schedule();
    });
    final connSub = Connectivity().onConnectivityChanged.listen((r) {
      if (r.any((x) => x != ConnectivityResult.none)) {
        syncNow();
      } else {
        state = state.copyWith(status: SyncStatus.offline);
      }
    });
    final lifecycle = AppLifecycleListener(
      onResume: () {
        syncNow();
        _startPolling();
      },
      onPause: () => _periodic?.cancel(),
    );
    ref.onDispose(pendingSub.cancel);
    ref.onDispose(connSub.cancel);
    ref.onDispose(lifecycle.dispose);

    _startPolling();
    Future.microtask(syncNow);
    return const SyncState(enabled: true);
  }

  void _startPolling() {
    _periodic?.cancel();
    _periodic = Timer.periodic(const Duration(seconds: 30), (_) => syncNow());
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 2), syncNow);
  }

  Future<void> syncNow() async {
    final engine = ref.read(syncEngineProvider);
    final hid = ref.read(householdIdProvider);
    if (!state.enabled || engine == null || hid == null) return;
    if (_running) {
      _again = true;
      return;
    }
    _running = true;
    state = state.copyWith(status: SyncStatus.syncing);
    try {
      var pushed = 0;
      final newTx = <TxEntry>[];
      do {
        _again = false;
        final report = await engine.run(hid);
        pushed += report.pushed;
        newTx.addAll(report.newTx);
      } while (_again);
      if (pushed > 0) unawaited(_announce(newTx));
      state = state.copyWith(status: SyncStatus.idle, lastSync: DateTime.now());
    } catch (e) {
      final s = e.toString();
      final offline = s.contains('SocketException') || s.contains('host lookup') || s.contains('ClientException');
      state = state.copyWith(status: offline ? SyncStatus.offline : SyncStatus.error, error: s);
    } finally {
      _running = false;
    }
  }

  /// Setelah perubahan lokal terkirim: kabari anggota lain.
  /// Transaksi baru -> push notification; perubahan lain -> hanya sinyal realtime.
  Future<void> _announce(List<TxEntry> newTx) async {
    final rt = ref.read(realtimeProvider.notifier);
    final mine = newTx.where((t) => t.createdBy == Neon.auth.currentUser?.id).toList();
    if (mine.isEmpty) return rt.notify(kind: 'sync');
    final name = ref.read(displayNameProvider).trim().split(' ').first;
    final who = name.isEmpty ? 'Pasanganmu' : name;
    if (mine.length > 1) {
      final total = mine.where((t) => t.kind == TxKind.expense).fold<int>(0, (s, t) => s + t.amount);
      return rt.notify(
        kind: 'tx',
        title: '$who mencatat ${mine.length} transaksi',
        body: total > 0 ? 'Total pengeluaran ${Rupiah.format(total)}' : 'Buka Aura untuk melihat detailnya',
      );
    }
    final t = mine.first;
    final cats = ref.read(categoryMapProvider);
    final what = switch (t.kind) { TxKind.income => 'pemasukan', TxKind.expense => 'pengeluaran', TxKind.transfer => 'transfer' };
    final detail = [cats[t.categoryId]?.name, if (t.note.isNotEmpty) t.note].whereType<String>().join(' · ');
    return rt.notify(kind: 'tx', title: '$who mencatat $what ${Rupiah.format(t.amount)}', body: detail);
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
