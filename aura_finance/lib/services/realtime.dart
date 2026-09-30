import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:pusher_channels_flutter/pusher_channels_flutter.dart';

import '../data/providers.dart';
import '../data/remote/neon.dart';
import '../data/sync/sync_providers.dart';

/// Konfigurasi realtime (nilai publik, diberikan saat build):
/// `--dart-define=AURA_API_URL=https://aura-api.<akun>.workers.dev`
/// `--dart-define=PUSHER_KEY=... --dart-define=PUSHER_CLUSTER=ap1`
abstract final class RealtimeConfig {
  static const apiUrl = String.fromEnvironment('AURA_API_URL');
  static const pusherKey = String.fromEnvironment('PUSHER_KEY');
  static const pusherCluster = String.fromEnvironment('PUSHER_CLUSTER', defaultValue: 'ap1');

  static bool get channelsEnabled => apiUrl.isNotEmpty && pusherKey.isNotEmpty && Neon.enabled;
  /// Push notification lewat Firebase Cloud Messaging (dikirim oleh worker).
  static bool get pushEnabled => apiUrl.isNotEmpty && Neon.enabled;
}

/// Status pendaftaran HP ini untuk push notification (saat aplikasi tertutup).
@immutable
class PushStatus {
  const PushStatus({this.registered = false, this.error});
  final bool registered;
  final String? error;
}

class PushStatusNotifier extends Notifier<PushStatus> {
  @override
  PushStatus build() => const PushStatus();
  void set(PushStatus s) => state = s;
}

final pushStatusProvider = NotifierProvider<PushStatusNotifier, PushStatus>(PushStatusNotifier.new);

/// Pesan dari anggota lain yang tiba lewat realtime (untuk toast di dalam aplikasi).
@immutable
class PartnerEvent {
  const PartnerEvent({required this.by, required this.kind, required this.title, required this.body});
  final String by;
  final String kind;
  final String title;
  final String body;
}

/// Menghubungkan rumah tangga ke Pusher:
/// - Channels: channel privat `private-household-<id>`; event `changed` memicu sinkron segera.
/// - Push: token FCM HP ini didaftarkan ke worker agar menerima push dari pasangan.
class RealtimeController extends Notifier<bool> {
  static const _push = MethodChannel('aura/push');
  final _events = StreamController<PartnerEvent>.broadcast();
  Stream<PartnerEvent> get events => _events.stream;

  PusherChannelsFlutter? _pusher;
  String? _channel;

  @override
  bool build() {
    final user = ref.watch(authUserProvider).value;
    final hid = ref.watch(householdIdProvider);
    ref.onDispose(_teardown);
    if (user == null || hid == null) return false;
    Future.microtask(() => _connect(user.id, hid));
    return RealtimeConfig.channelsEnabled;
  }

  Future<void> _connect(String userId, String hid) async {
    if (RealtimeConfig.channelsEnabled) {
      try {
        final pusher = PusherChannelsFlutter.getInstance();
        await pusher.init(
          apiKey: RealtimeConfig.pusherKey,
          cluster: RealtimeConfig.pusherCluster,
          onAuthorizer: (channelName, socketId, options) => _authorize(channelName, socketId),
          onEvent: (e) => _onEvent(e, userId),
          onConnectionStateChange: (current, previous) {
            // Tersambung kembali setelah putus -> tarik data yang mungkin terlewat.
            if (current == 'CONNECTED' && previous != 'CONNECTED') {
              ref.read(syncControllerProvider.notifier).syncNow();
            }
          },
        );
        _channel = 'private-household-$hid';
        await pusher.subscribe(channelName: _channel!);
        await pusher.connect();
        _pusher = pusher;
      } catch (e) {
        debugPrint('Pusher Channels gagal: $e');
      }
    }
    await registerPush(userId);
  }

  /// Mendaftarkan token FCM HP ini ke worker untuk pengguna [userId]. Hasilnya dicatat di
  /// [pushStatusProvider] supaya bisa dilihat di halaman Rumah Tangga.
  Future<void> registerPush(String userId) async {
    final status = ref.read(pushStatusProvider.notifier);
    if (!RealtimeConfig.pushEnabled) {
      status.set(const PushStatus(error: 'Push belum dikonfigurasi di aplikasi ini'));
      return;
    }
    String? token;
    try {
      token = await _push.invokeMethod<String>('fcmToken').timeout(const Duration(seconds: 20));
    } on TimeoutException {
      status.set(const PushStatus(error: 'Firebase tidak merespons (cek Google Play Services & koneksi)'));
      return;
    } on PlatformException catch (e) {
      status.set(PushStatus(error: 'Firebase: ${e.message ?? e.code}'));
      return;
    }
    if (token == null || token.isEmpty) {
      status.set(const PushStatus(error: 'Firebase tidak memberi token'));
      return;
    }
    try {
      final res = await http
          .post(
            Uri.parse('${RealtimeConfig.apiUrl}/push/register'),
            headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) {
        status.set(PushStatus(error: 'Server menolak pendaftaran (${res.statusCode})'));
        return;
      }
      await ref.read(prefsProvider).setString(_kToken, token);
      status.set(const PushStatus(registered: true));
    } catch (e) {
      status.set(PushStatus(error: e is TimeoutException ? 'Server tidak merespons' : 'Tidak bisa menghubungi server'));
    }
  }

  static const _kToken = 'fcm_token';

  /// Dipanggil sebelum keluar akun: HP ini berhenti menerima push untuk akun tersebut.
  Future<void> unregisterPush() async {
    final token = ref.read(prefsProvider).getString(_kToken);
    if (token == null || RealtimeConfig.apiUrl.isEmpty || Neon.auth.currentUser == null) return;
    try {
      await http
          .post(
            Uri.parse('${RealtimeConfig.apiUrl}/push/unregister'),
            headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
            body: jsonEncode({'token': token}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
    await ref.read(prefsProvider).remove(_kToken);
  }

  /// Minta server mengirim push uji ke HP ini sendiri beberapa detik lagi,
  /// supaya pengguna sempat menutup aplikasi dan melihatnya muncul.
  Future<bool> sendTestPush() async {
    final hid = ref.read(householdIdProvider);
    if (RealtimeConfig.apiUrl.isEmpty || hid == null || Neon.auth.currentUser == null) return false;
    try {
      final res = await http.post(
        Uri.parse('${RealtimeConfig.apiUrl}/notify'),
        headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
        body: jsonEncode({'household_id': hid, 'kind': 'test', 'title': 'Notifikasi Aura aktif', 'body': 'Kabar dari pasanganmu akan muncul seperti ini.'}),
      );
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<void> openNotificationSettings() async {
    try {
      await _push.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  Future<Map<String, dynamic>> _authorize(String channelName, String socketId) async {
    final res = await http.post(
      Uri.parse('${RealtimeConfig.apiUrl}/pusher/auth'),
      headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
      body: jsonEncode({'socket_id': socketId, 'channel_name': channelName}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _onEvent(PusherEvent e, String me) async {
    if (e.eventName != 'changed') return;
    Map<String, dynamic> data;
    try {
      data = jsonDecode(e.data as String) as Map<String, dynamic>;
    } catch (_) {
      data = const {};
    }
    final sync = ref.read(syncControllerProvider.notifier);
    final hid = ref.read(householdIdProvider);
    final engine = ref.read(syncEngineProvider);
    // 1) Terapkan isi perubahan yang ikut di sinyal -> layar langsung berubah.
    final changes = data['changes'];
    if (changes is Map<String, dynamic> && hid != null && engine != null) {
      try {
        await engine.applyChanges(changes, hid);
      } catch (err) {
        debugPrint('applyChanges gagal: $err');
      }
    }
    // 2) Tarik versi resmi dari server, hanya tabel yang berubah bila disebutkan.
    final tables = (data['tables'] as List?)?.whereType<String>().toSet();
    unawaited(sync.syncNow(tables: tables == null || tables.isEmpty ? null : tables));
    final by = data['by'] as String? ?? '';
    final title = data['title'] as String? ?? '';
    if (by != me && title.isNotEmpty) {
      _events.add(PartnerEvent(by: by, kind: data['kind'] as String? ?? '', title: title, body: data['body'] as String? ?? ''));
    }
  }

  /// Memberi tahu anggota lain (realtime + push). Gagal diam-diam saat offline.
  /// Untuk kabar dari UI (tagihan, target, budget) data dikirim dulu ke Neon,
  /// supaya HP pasangan yang menerima sinyal langsung menarik data terbaru.
  /// Batas ukuran isi perubahan yang ikut di sinyal (event Pusher maksimal 10 KB).
  static const _maxChangesBytes = 7000;

  Future<void> notify({
    required String kind,
    String title = '',
    String body = '',
    Map<String, List<Map<String, dynamic>>> changes = const {},
  }) async {
    final hid = ref.read(householdIdProvider);
    if (RealtimeConfig.apiUrl.isEmpty || hid == null || Neon.auth.currentUser == null) return;
    try {
      if (kind != 'tx' && kind != 'sync') await ref.read(syncControllerProvider.notifier).syncNow();
      final socketId = _pusher == null ? null : await _pusher!.getSocketId();
      final payload = <String, dynamic>{'household_id': hid, 'kind': kind, 'title': title, 'body': body, 'socket_id': socketId};
      if (changes.isNotEmpty) {
        payload['tables'] = changes.keys.toList();
        final visible = {for (final e in changes.entries) if (e.value.isNotEmpty) e.key: e.value};
        if (visible.isNotEmpty && utf8.encode(jsonEncode(visible)).length <= _maxChangesBytes) payload['changes'] = visible;
      }
      await http.post(
        Uri.parse('${RealtimeConfig.apiUrl}/notify'),
        headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('notify gagal: $e');
    }
  }

  Future<void> _teardown() async {
    final p = _pusher;
    final ch = _channel;
    _pusher = null;
    _channel = null;
    if (p != null) {
      if (ch != null) await p.unsubscribe(channelName: ch).catchError((_) {});
      await p.disconnect().catchError((_) {});
    }
  }
}

final realtimeProvider = NotifierProvider<RealtimeController, bool>(RealtimeController.new);
