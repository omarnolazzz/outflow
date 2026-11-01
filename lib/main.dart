import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'app.dart';
import 'core/config/firebase_config.dart';
import 'core/di/core_providers.dart';
import 'core/storage/local_store.dart';
import 'core/utils/formatters.dart';
import 'features/notifications/data/local_notification_service.dart';
import 'features/notifications/presentation/notification_providers.dart';

/// Todo lo que se prepara antes de la primera pantalla va protegido: si un
/// paso falla o no responde, la app sigue sin él. Un error aquí sin capturar
/// dejaba la app colgada para siempre en el logo del sistema.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final locale = Fmt.resolveLocale(PlatformDispatcher.instance.locale.countryCode);
  Intl.defaultLocale = locale;
  await _step('formato de fechas', () => initializeDateFormatting(locale));

  const secure = FlutterSecureStorage();
  LocalStore? store;
  Object? storeError;
  try {
    store = await LocalStore.open(secure).timeout(const Duration(seconds: 20));
  } catch (e, s) {
    debugPrint('No se pudo abrir el almacén local: $e\n$s');
    storeError = e;
  }

  final notifications = LocalNotificationService();
  await _step('notificaciones', notifications.init);

  // Cuenta Google real solo con la configuración inyectada al compilar.
  if (!kIsWeb && FirebaseConfig.isConfigured) {
    await _step('Firebase', () async {
      await Firebase.initializeApp(options: FirebaseConfig.options);
      FirebaseConfig.initialized = true;
    });
  }

  if (store == null) {
    runApp(StartupErrorApp(error: storeError));
    return;
  }

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

/// Ejecuta un paso de arranque opcional con tiempo límite; si falla, sigue.
Future<void> _step(String name, Future<void> Function() run) async {
  try {
    await run().timeout(const Duration(seconds: 10));
  } catch (e) {
    debugPrint('Arranque: se omite $name ($e)');
  }
}

/// Último recurso si ni siquiera se pueden abrir los datos del teléfono:
/// mejor un mensaje claro (con el error para soporte) que una pantalla congelada.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, this.error});
  final Object? error;

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'Outflow no pudo abrir sus datos',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Cierra la app y vuelve a abrirla. Si sigue igual, reinstálala.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  SelectableText(
                    '$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF6E6E73)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
