import 'dart:ui' show Color;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../core/utils/rupiah.dart';
import '../data/local/database.dart';
import '../data/providers.dart';

/// Notifikasi lokal: pengingat tagihan (terjadwal) & peringatan budget (langsung).
class Notifications {
  Notifications(this.db, this.prefs);
  final AppDatabase db;
  final SharedPreferences prefs;

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static const _billChannel = AndroidNotificationDetails(
    'bills',
    'Pengingat tagihan',
    channelDescription: 'Diingatkan sebelum tagihan jatuh tempo',
    importance: Importance.high,
    priority: Priority.high,
    color: _rose,
  );
  static const _budgetChannel = AndroidNotificationDetails(
    'budget',
    'Peringatan budget',
    channelDescription: 'Saat pemakaian budget mencapai 80% dan 100%',
    importance: Importance.defaultImportance,
    color: _rose,
  );
  static const _rose = Color(0xFFFE64A3);

  static Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Jakarta'));
    }
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@drawable/ic_notification')),
    );
    // Kanal untuk push dari pasangan (dipakai FCM/Pusher Beams).
    await _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(
          const AndroidNotificationChannel('household', 'Kabar rumah tangga', description: 'Catatan, budget, target & tagihan dari anggota lain', importance: Importance.high),
        );
    _ready = true;
  }

  /// Meminta izin notifikasi (Android 13+). Mengembalikan status akhirnya.
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return true;
    return await android.requestNotificationsPermission() ?? await enabled();
  }

  /// Apakah aplikasi boleh menampilkan notifikasi di luar aplikasi.
  Future<bool> enabled() async {
    await init();
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    return await android?.areNotificationsEnabled() ?? true;
  }

  /// Menjadwalkan ulang semua pengingat tagihan yang belum dibayar.
  Future<void> rescheduleBills() async {
    await init();
    final old = prefs.getStringList('bill_notif_ids') ?? const [];
    for (final id in old) {
      await _plugin.cancel(id: int.parse(id));
    }
    final bills = await db.watchBills().first;
    final now = tz.TZDateTime.now(tz.local);
    final ids = <String>[];
    for (final b in bills.where((b) => b.paidAt == null)) {
      final due = tz.TZDateTime(tz.local, b.dueDate.year, b.dueDate.month, b.dueDate.day, 9);
      final plan = [
        (due.subtract(Duration(days: b.remindDaysBefore)), '${b.name} jatuh tempo ${b.remindDaysBefore} hari lagi'),
        (due, '${b.name} jatuh tempo hari ini'),
      ];
      for (final (i, (at, title)) in plan.indexed) {
        if (!at.isAfter(now)) continue;
        final id = (b.id.hashCode & 0x3fffffff) + i;
        await _plugin.zonedSchedule(
          id: id,
          scheduledDate: at,
          title: title,
          body: 'Sebesar ${Rupiah.format(b.amount)}. Ketuk untuk menandai lunas.',
          notificationDetails: const NotificationDetails(android: _billChannel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
        ids.add('$id');
      }
    }
    await prefs.setStringList('bill_notif_ids', ids);
  }

  /// Peringatan budget, sekali per budget per ambang (80/100).
  /// Mengembalikan `true` jika peringatan ini baru pertama kali dikirim.
  Future<bool> budgetAlert({required String budgetId, required String category, required int threshold, required int spent, required int limit}) async {
    final key = 'budget_alert_${budgetId}_$threshold';
    if (prefs.getBool(key) ?? false) return false;
    await prefs.setBool(key, true);
    await init();
    await _plugin.show(
      id: (budgetId.hashCode & 0x3fffffff) + threshold,
      title: threshold >= 100 ? 'Budget $category terlampaui' : 'Budget $category sudah $threshold%',
      body: '${Rupiah.format(spent)} dari ${Rupiah.format(limit)} terpakai bulan ini.',
      notificationDetails: const NotificationDetails(android: _budgetChannel),
    );
    return true;
  }
}

final notificationsProvider = Provider<Notifications>((ref) => Notifications(ref.watch(dbProvider), ref.watch(prefsProvider)));
