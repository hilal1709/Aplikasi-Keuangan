import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'data/local/database.dart';
import 'data/providers.dart';
import 'data/remote/neon.dart';
import 'services/background.dart';
import 'services/notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID');
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final prefs = await SharedPreferences.getInstance();
  await Neon.init();
  await Notifications.init();
  Background.register().ignore();

  runApp(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(AppDatabase()),
        prefsProvider.overrideWithValue(prefs),
      ],
      child: const AuraApp(),
    ),
  );
}
