import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Una app cuyas notificaciones se pueden leer: su paquete y su nombre.
@immutable
class CaptureApp {
  const CaptureApp({required this.package, required this.label});

  final String package;
  final String label;
}

/// Permiso de Android para leer las notificaciones y qué apps se leen. Los textos
/// con pinta de pago los deja el servicio nativo en la bandeja de captura.
abstract interface class PaymentListener {
  Future<bool> isEnabled();
  Future<void> openSettings();

  /// Apps conocidas y apps vistas con un aviso de dinero.
  Future<List<CaptureApp>> seenApps();

  /// Paquetes que se leen ahora.
  Future<Set<String>> enabledApps();
  Future<void> setEnabled(String package, bool enabled);
}

class ChannelPaymentListener implements PaymentListener {
  const ChannelPaymentListener();

  static const _channel = MethodChannel('outflow/payments');

  @override
  Future<bool> isEnabled() async {
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } on PlatformException {
      // Sin ajustes que abrir: no hay nada más que hacer.
    } on MissingPluginException {
      // Idem (vista previa web).
    }
  }

  @override
  Future<List<CaptureApp>> seenApps() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>('seenApps') ?? const [];
      return [
        for (final m in raw)
          CaptureApp(package: m['package']! as String, label: (m['label'] as String?) ?? m['package']! as String),
      ];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  @override
  Future<Set<String>> enabledApps() async {
    try {
      return (await _channel.invokeListMethod<String>('enabledApps') ?? const []).toSet();
    } on PlatformException {
      return {};
    } on MissingPluginException {
      return {};
    }
  }

  @override
  Future<void> setEnabled(String package, bool enabled) async {
    try {
      await _channel.invokeMethod<void>('setEnabled', {'package': package, 'enabled': enabled});
    } on PlatformException {
      // Sin canal no hay nada que guardar.
    } on MissingPluginException {
      // Idem (vista previa web).
    }
  }
}

final paymentListenerProvider = Provider<PaymentListener>((ref) => const ChannelPaymentListener());

/// Android (no web): el registro de pagos va por notificaciones, no por Atajos.
bool get isAndroidDevice => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
