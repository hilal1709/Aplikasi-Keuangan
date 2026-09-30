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
/// `--dart-define=PUSHER_KEY=... --dart-define=PUSHER_CLUSTER=ap1 --dart-define=BEAMS_INSTANCE_ID=...`
abstract final class RealtimeConfig {
  static const apiUrl = String.fromEnvironment('AURA_API_URL');
  static const pusherKey = String.fromEnvironment('PUSHER_KEY');
  static const pusherCluster = String.fromEnvironment('PUSHER_CLUSTER', defaultValue: 'ap1');
  static const beamsInstanceId = String.fromEnvironment('BEAMS_INSTANCE_ID');

  static bool get channelsEnabled => apiUrl.isNotEmpty && pusherKey.isNotEmpty && Neon.enabled;
  static bool get beamsEnabled => apiUrl.isNotEmpty && beamsInstanceId.isNotEmpty && Neon.enabled;
}

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
/// - Beams: mendaftarkan HP ini sebagai user Beams agar menerima push dari pasangan.
class RealtimeController extends Notifier<bool> {
  static const _beams = MethodChannel('aura/beams');
  final _events = StreamController<PartnerEvent>.broadcast();
  Stream<PartnerEvent> get events => _events.stream;

  PusherChannelsFlutter? _pusher;
  String? _channel;

  @override
  bool build() {
    final user = ref.watch(authUserProvider).value;
    final hid = ref.watch(householdIdProvider);
    ref.onDispose(_teardown);
    if (user == null || hid == null) {
      if (user == null) _clearBeams();
      return false;
    }
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
    if (RealtimeConfig.beamsEnabled) {
      try {
        final started = await _beams.invokeMethod<bool>('start', {'instanceId': RealtimeConfig.beamsInstanceId});
        if (started == true) {
          await _beams.invokeMethod('setUser', {
            'userId': userId,
            'tokenUrl': '${RealtimeConfig.apiUrl}/beams/token',
            'jwt': await Neon.auth.accessToken(),
          });
        }
      } catch (e) {
        debugPrint('Pusher Beams gagal: $e');
      }
    }
  }

  Future<Map<String, dynamic>> _authorize(String channelName, String socketId) async {
    final res = await http.post(
      Uri.parse('${RealtimeConfig.apiUrl}/pusher/auth'),
      headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
      body: jsonEncode({'socket_id': socketId, 'channel_name': channelName}),
    );
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _onEvent(PusherEvent e, String me) {
    if (e.eventName != 'changed') return;
    ref.read(syncControllerProvider.notifier).syncNow();
    try {
      final data = jsonDecode(e.data as String) as Map<String, dynamic>;
      final by = data['by'] as String? ?? '';
      final title = data['title'] as String? ?? '';
      if (by != me && title.isNotEmpty) {
        _events.add(PartnerEvent(by: by, kind: data['kind'] as String? ?? '', title: title, body: data['body'] as String? ?? ''));
      }
    } catch (_) {}
  }

  /// Memberi tahu anggota lain (realtime + push). Gagal diam-diam saat offline.
  /// Untuk kabar dari UI (tagihan, target, budget) data dikirim dulu ke Neon,
  /// supaya HP pasangan yang menerima sinyal langsung menarik data terbaru.
  Future<void> notify({required String kind, String title = '', String body = ''}) async {
    final hid = ref.read(householdIdProvider);
    if (RealtimeConfig.apiUrl.isEmpty || hid == null || Neon.auth.currentUser == null) return;
    try {
      if (kind != 'tx' && kind != 'sync') await ref.read(syncControllerProvider.notifier).syncNow();
      final socketId = _pusher == null ? null : await _pusher!.getSocketId();
      await http.post(
        Uri.parse('${RealtimeConfig.apiUrl}/notify'),
        headers: {'Authorization': 'Bearer ${await Neon.auth.accessToken()}', 'Content-Type': 'application/json'},
        body: jsonEncode({'household_id': hid, 'kind': kind, 'title': title, 'body': body, 'socket_id': socketId}),
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

  Future<void> _clearBeams() async {
    if (!RealtimeConfig.beamsEnabled) return;
    try {
      await _beams.invokeMethod('clear');
    } catch (_) {}
  }
}

final realtimeProvider = NotifierProvider<RealtimeController, bool>(RealtimeController.new);
