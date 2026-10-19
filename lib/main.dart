import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/di/core_providers.dart';
import 'core/storage/local_store.dart';
import 'core/utils/formatters.dart';
import 'features/notifications/data/local_notification_service.dart';
import 'features/notifications/presentation/notification_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final locale = Fmt.resolveLocale(PlatformDispatcher.instance.locale.countryCode);
  Intl.defaultLocale = locale;
  await initializeDateFormatting(locale);

  const secure = FlutterSecureStorage();
  final store = await LocalStore.open(secure);
  final notifications = LocalNotificationService();
  await notifications.init();

  runApp(
    ProviderScope(
      overrides: [
        secureStorageProvider.overrideWithValue(secure),
        localStoreProvider.overrideWithValue(store),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const OutflowApp(),
    ),
  );
}
