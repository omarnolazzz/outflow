import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Permiso de Android para leer las notificaciones de pago (Google Pay y
/// bancos). Los pagos detectados llegan como enlaces `outflow://gasto?…`.
abstract interface class PaymentListener {
  Future<bool> isEnabled();
  Future<void> openSettings();
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
}

final paymentListenerProvider = Provider<PaymentListener>((ref) => const ChannelPaymentListener());

/// Android (no web): el registro de pagos va por notificaciones, no por Atajos.
bool get isAndroidDevice => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
