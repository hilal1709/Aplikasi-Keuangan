import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/splash.dart';
import 'data/local/database.dart';
import 'data/providers.dart';
import 'data/remote/neon.dart';
import 'services/background.dart';
import 'services/notifications.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  runApp(
    BootGate(
      init: () async {
        await initializeDateFormatting('id_ID');
        final prefs = await SharedPreferences.getInstance();
        await Neon.init();
        await Notifications.init();
        Background.register().ignore();
        return prefs;
      },
      builder: (prefs) => ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(AppDatabase()),
          prefsProvider.overrideWithValue(prefs! as SharedPreferences),
        ],
        child: const AuraApp(),
      ),
    ),
  );
}
