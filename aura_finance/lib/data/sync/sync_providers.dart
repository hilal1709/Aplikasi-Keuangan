import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/rupiah.dart';
import '../../core/widgets/feedback.dart';
import '../../services/realtime.dart';
import '../local/database.dart';
import '../providers.dart';
import '../remote/household_service.dart';
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
/// saat ada perubahan lokal (ditunda sebentar untuk mengumpulkan ketikan beruntun),
/// saat sinyal Pusher dari anggota lain tiba, dan berkala (cadangan bila realtime putus).
class SyncController extends Notifier<SyncState> {
  Timer? _debounce;
  Timer? _periodic;
  bool _running = false;
  bool _again = false;

  /// Jeda sebelum mengirim perubahan lokal. Pendek supaya pasangan cepat melihatnya,
  /// cukup untuk menggabungkan beberapa penulisan dari satu aksi.
  static const pushDelay = Duration(milliseconds: 250);

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
    _debounce = Timer(pushDelay, syncNow);
  }

  /// Kirim perubahan lokal, kabari anggota lain, lalu tarik perubahan.
  /// [tables] membatasi penarikan ke tabel tertentu (dari sinyal realtime).
  Future<void> syncNow({Set<String>? tables}) async {
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
      var only = tables;
      var full = false;
      do {
        _again = false;
        final report = await engine.push(hid);
        // Sinyal dikirim segera setelah data sampai di server, tidak menunggu tarikan.
        if (report.pushed > 0) unawaited(_announce(report));
        await engine.pull(hid, tables: only);
        full = full || only == null;
        only = null; // putaran ulang selalu menarik semua
      } while (_again);
      state = state.copyWith(status: SyncStatus.idle, lastSync: DateTime.now());
      // Dikeluarkan pemilik dari HP lain: daftar anggota tidak lagi memuat kita.
      final me = Neon.auth.currentUser?.id;
      if (full && me != null && !await engine.isMember(hid, me)) await _removed(hid);
    } catch (e) {
      final s = e.toString();
      final offline = s.contains('SocketException') || s.contains('host lookup') || s.contains('ClientException');
      state = state.copyWith(status: offline ? SyncStatus.offline : SyncStatus.error, error: s);
    } finally {
      _running = false;
    }
  }

  Future<void> _removed(String hid) async {
    String? name;
    try {
      name = (await ref.read(householdServiceProvider).current())?.name;
    } catch (_) {}
    await ref.read(householdServiceProvider).detach(hid);
    AuraToast.global(
      title: 'Kamu tidak lagi menjadi anggota',
      message: 'Pemilik mengeluarkanmu dari ${name ?? 'rumah tangga'}. Datanya sudah dilepas dari HP ini.',
      tone: AuraTone.warning,
    );
  }

  /// Setelah perubahan lokal terkirim: kabari anggota lain.
  /// Transaksi baru di dompet bersama -> push notification; perubahan lain -> hanya sinyal realtime.
  /// Tidak dikabarkan: transaksi di dompet pribadi, dan pengeluaran otomatis dari pelunasan
  /// tagihan (sudah ada notifikasi "Tagihan lunas" sendiri, jadi tidak dobel).
  Future<void> _announce(SyncReport report) async {
    final rt = ref.read(realtimeProvider.notifier);
    final changes = report.changes;
    final sharedIds = {for (final r in changes['transactions'] ?? const <Map<String, dynamic>>[]) r['id']};
    final mine = report.newTx
        .where((t) => t.createdBy == Neon.auth.currentUser?.id && sharedIds.contains(t.id) && t.billId == null)
        .toList();
    if (mine.isEmpty) return rt.notify(kind: 'sync', changes: changes);
    final name = ref.read(displayNameProvider).trim().split(' ').first;
    final who = name.isEmpty ? 'Pasanganmu' : name;
    final cats = ref.read(categoryMapProvider);
    final auto = mine.every((t) => t.recurringRuleId != null);
    if (mine.length > 1) {
      final total = mine.where((t) => t.kind == TxKind.expense).fold<int>(0, (s, t) => s + t.amount);
      return rt.notify(
        kind: 'tx',
        title: auto ? '${mine.length} transaksi berulang tercatat' : '$who mencatat ${mine.length} transaksi',
        body: total > 0 ? 'Total pengeluaran ${Rupiah.format(total)}' : 'Buka Aura untuk melihat detailnya',
        changes: changes,
      );
    }
    final t = mine.first;
    final what = switch (t.kind) { TxKind.income => 'pemasukan', TxKind.expense => 'pengeluaran', TxKind.transfer => 'transfer' };
    final detail = [cats[t.categoryId]?.name, if (t.note.isNotEmpty) t.note].whereType<String>().join(' · ');
    return rt.notify(
      kind: 'tx',
      title: auto ? '${t.note.isNotEmpty ? t.note : 'Transaksi berulang'} tercatat otomatis' : '$who mencatat $what ${Rupiah.format(t.amount)}',
      body: auto ? '${what[0].toUpperCase()}${what.substring(1)} ${Rupiah.format(t.amount)}${detail.isEmpty ? '' : ' · $detail'}' : detail,
      changes: changes,
    );
  }
}

final syncControllerProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
