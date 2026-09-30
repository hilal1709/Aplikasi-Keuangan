import 'package:flutter/widgets.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/local/database.dart';
import 'home_widget_sync.dart';
import 'notifications.dart';
import 'recurring_runner.dart';

const _task = 'aura.daily';

/// Titik masuk isolate latar belakang WorkManager.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, _) async {
    WidgetsFlutterBinding.ensureInitialized();
    await initializeDateFormatting('id_ID');
    final db = AppDatabase();
    try {
      final prefs = await SharedPreferences.getInstance();
      await runDueRecurring(db);
      await Notifications(db, prefs).rescheduleBills();
      await HomeWidgetSync.push(db);
      return true;
    } catch (_) {
      return false;
    } finally {
      await db.close();
    }
  });
}

abstract final class Background {
  static Future<void> register() async {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      _task,
      _task,
      frequency: const Duration(hours: 6),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }
}
