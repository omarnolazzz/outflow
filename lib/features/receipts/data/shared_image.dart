import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Una imagen que otra app compartió con Outflow (Android: Compartir → Outflow),
/// ya copiada a la caché; quien la lee la borra después.
abstract interface class SharedImageSource {
  /// La imagen con la que se abrió la app, una sola vez; null si no hubo.
  /// Lanza [SharedImageFailed] si no se pudo copiar.
  Future<String?> initialImage();

  /// Imágenes que llegan con la app abierta. Un error de copia sale como [SharedImageFailed].
  Stream<String> get images;
}

class SharedImageFailed implements Exception {
  const SharedImageFailed();
}

final sharedImageSourceProvider = Provider<SharedImageSource>(
  (ref) => kIsWeb ? const NoSharedImages() : ChannelSharedImageSource(),
);

class NoSharedImages implements SharedImageSource {
  const NoSharedImages();

  @override
  Future<String?> initialImage() async => null;

  @override
  Stream<String> get images => const Stream.empty();
}

/// Canal `outflow/share` de Android. En iPhone no responde y no hay nada que leer.
class ChannelSharedImageSource implements SharedImageSource {
  ChannelSharedImageSource([MethodChannel? channel]) : _channel = channel ?? const MethodChannel('outflow/share');

  final MethodChannel _channel;
  final _controller = StreamController<String>.broadcast();
  bool _listening = false;

  void _listen() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'image') {
        final path = call.arguments as String?;
        if (path != null) _controller.add(path);
      } else if (call.method == 'failed') {
        _controller.addError(const SharedImageFailed());
      }
      return null;
    });
  }

  @override
  Future<String?> initialImage() async {
    _listen();
    try {
      return await _channel.invokeMethod<String>('initialImage');
    } on PlatformException {
      throw const SharedImageFailed();
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Stream<String> get images {
    _listen();
    return _controller.stream;
  }
}
