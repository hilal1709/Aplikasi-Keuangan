import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:postgrest/postgrest.dart';

/// Konfigurasi Neon, diberikan saat build:
/// `flutter run --dart-define=NEON_DATA_API_URL=https://ep-xxx.apirest.REGION.aws.neon.tech/neondb/rest/v1
///              --dart-define=NEON_AUTH_URL=https://ep-xxx.neonauth.REGION.aws.neon.tech/neondb/auth`
/// Tanpa itu aplikasi berjalan penuh dalam mode lokal (offline saja).
abstract final class NeonConfig {
  static const dataApiUrl = String.fromEnvironment('NEON_DATA_API_URL');
  static const authUrl = String.fromEnvironment('NEON_AUTH_URL');
  static bool get enabled => dataApiUrl.isNotEmpty && authUrl.isNotEmpty;
}

@immutable
class NeonUser {
  const NeonUser({required this.id, required this.email, this.name = ''});
  final String id;
  final String email;
  final String name;

  Map<String, dynamic> toJson() => {'id': id, 'email': email, 'name': name};
  factory NeonUser.fromJson(Map<String, dynamic> j) =>
      NeonUser(id: j['id'] as String, email: (j['email'] as String?) ?? '', name: (j['name'] as String?) ?? '');
}

class NeonAuthException implements Exception {
  NeonAuthException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// Klien Neon Auth (Managed Better Auth) lewat HTTP biasa.
///
/// Alur: sign-in/sign-up -> server memberi cookie sesi (disimpan aman di perangkat)
/// -> cookie ditukar ke JWT pendek (~15 menit) lewat `GET /token`
/// -> JWT dikirim sebagai `Authorization: Bearer` ke Data API, yang menegakkan RLS.
class NeonAuth {
  NeonAuth._();
  static final instance = NeonAuth._();

  static const _storage = FlutterSecureStorage();
  static const _kCookie = 'neon_session_cookie';
  static const _kUser = 'neon_user';

  final _userCtrl = StreamController<NeonUser?>.broadcast();
  String? _cookie;
  NeonUser? _user;
  String? _jwt;
  DateTime? _jwtExp;
  Future<String>? _refreshing;

  NeonUser? get currentUser => _user;
  Stream<NeonUser?> get onUserChanged => _userCtrl.stream;

  Uri _u(String path) => Uri.parse('${NeonConfig.authUrl.replaceAll(RegExp(r'/$'), '')}/$path');

  Future<void> restore() async {
    if (!NeonConfig.enabled) return;
    _cookie = await _storage.read(key: _kCookie);
    final u = await _storage.read(key: _kUser);
    if (_cookie != null && u != null) _user = NeonUser.fromJson(jsonDecode(u) as Map<String, dynamic>);
  }

  Future<NeonUser> signUp({required String email, required String password, required String name}) =>
      _authPost('sign-up/email', {'email': email, 'password': password, 'name': name.isEmpty ? email.split('@').first : name});

  Future<NeonUser> signIn({required String email, required String password}) =>
      _authPost('sign-in/email', {'email': email, 'password': password});

  Future<NeonUser> _authPost(String path, Map<String, dynamic> body) async {
    final res = await http.post(_u(path), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body));
    final json = res.body.isEmpty ? <String, dynamic>{} : jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode >= 400) {
      throw NeonAuthException((json['message'] as String?) ?? (json['code'] as String?) ?? 'Gagal (${res.statusCode})', status: res.statusCode);
    }
    final cookie = _sessionCookie(res.headers['set-cookie']);
    if (cookie == null) {
      // Sebagian konfigurasi mewajibkan verifikasi email sebelum sesi dibuat.
      throw NeonAuthException('Cek email untuk verifikasi akun, lalu masuk.', status: 200);
    }
    final user = NeonUser.fromJson(json['user'] as Map<String, dynamic>);
    _cookie = cookie;
    _user = user;
    _jwt = null;
    await _storage.write(key: _kCookie, value: cookie);
    await _storage.write(key: _kUser, value: jsonEncode(user.toJson()));
    _userCtrl.add(user);
    return user;
  }

  /// Mengambil pasangan `nama=nilai` cookie sesi dari header Set-Cookie
  /// (package:http menggabungkan beberapa Set-Cookie dengan koma).
  String? _sessionCookie(String? header) {
    if (header == null) return null;
    final m = RegExp(r'((?:__Secure-)?[\w.-]*session_token)=([^;,\s]+)').firstMatch(header);
    return m == null ? null : '${m[1]}=${m[2]}';
  }

  /// JWT yang masih berlaku (diperbarui otomatis ±1 menit sebelum kedaluwarsa).
  Future<String> accessToken() {
    final exp = _jwtExp;
    if (_jwt != null && exp != null && exp.isAfter(DateTime.now().add(const Duration(minutes: 1)))) {
      return Future.value(_jwt!);
    }
    return _refreshing ??= _fetchJwt().whenComplete(() => _refreshing = null);
  }

  Future<String> _fetchJwt() async {
    if (_cookie == null) throw NeonAuthException('Belum masuk', status: 401);
    final res = await http.get(_u('token'), headers: {'Cookie': _cookie!});
    if (res.statusCode == 401) {
      await signOut();
      throw NeonAuthException('Sesi berakhir, silakan masuk lagi', status: 401);
    }
    if (res.statusCode >= 400) throw NeonAuthException('Gagal mengambil token (${res.statusCode})', status: res.statusCode);
    final token = (jsonDecode(res.body) as Map<String, dynamic>)['token'] as String? ?? res.headers['set-auth-jwt'];
    if (token == null) throw NeonAuthException('Token tidak ditemukan');
    _jwt = token;
    _jwtExp = _expiry(token);
    return token;
  }

  DateTime _expiry(String jwt) {
    try {
      final payload = jwt.split('.')[1];
      final map = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(payload)))) as Map<String, dynamic>;
      return DateTime.fromMillisecondsSinceEpoch((map['exp'] as int) * 1000);
    } catch (_) {
      return DateTime.now().add(const Duration(minutes: 10));
    }
  }

  Future<void> signOut() async {
    final cookie = _cookie;
    _cookie = null;
    _user = null;
    _jwt = null;
    await _storage.delete(key: _kCookie);
    await _storage.delete(key: _kUser);
    _userCtrl.add(null);
    if (cookie != null) {
      unawaited(http.post(_u('sign-out'), headers: {'Cookie': cookie, 'Content-Type': 'application/json'}, body: '{}').catchError((_) => http.Response('', 0)));
    }
  }
}

/// Klien Data API (PostgREST-kompatibel). Setiap pemanggilan memakai JWT segar.
abstract final class Neon {
  static bool get enabled => NeonConfig.enabled;
  static NeonAuth get auth => NeonAuth.instance;

  static Future<PostgrestClient> db() async {
    final token = await auth.accessToken();
    return PostgrestClient(NeonConfig.dataApiUrl, headers: {'Authorization': 'Bearer $token'});
  }

  static Future<void> init() => auth.restore();
}
