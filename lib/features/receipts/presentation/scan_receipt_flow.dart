import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/di/core_providers.dart';
import '../../../core/motion/app_motion.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../data/gemini_receipt_reader.dart';
import '../data/text_recognizer.dart';
import '../domain/receipt.dart';
import 'receipt_result_screen.dart';

/// Elige una foto (cámara o galería) y devuelve su ruta; null si se cancela.
final imagePickerProvider = Provider<Future<String?> Function(bool fromCamera)>((ref) => (fromCamera) async {
      final file = await ImagePicker().pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 2400,
        imageQuality: 90,
      );
      return file?.path;
    });

/// "Escanear ticket": pregunta cámara o galería y sigue el flujo.
///
/// Recibe un contexto que siga montado durante todo el flujo (el del navegador
/// raíz), no el de una hoja que se cierra: no usa su `ref`.
Future<void> showScanReceipt(BuildContext context) async {
  final fromCamera = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Escanear ticket', style: AppType.title2),
            const SizedBox(height: 4),
            Text('La foto se lee en tu iPhone y no se guarda.', style: AppType.subhead),
            const SizedBox(height: 18),
            PrimaryButton(
              label: 'Tomar foto',
              icon: const Icon(LucideIcons.camera, size: 18, color: AppColors.onAccent),
              onTap: () => Navigator.pop(context, true),
            ),
            const SizedBox(height: 10),
            PrimaryButton(
              label: 'Elegir de la galería',
              secondary: true,
              icon: const Icon(LucideIcons.image, size: 18, color: AppColors.ink),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    ),
  );
  if (fromCamera == null || !context.mounted) return;
  await scanReceipt(context, fromCamera: fromCamera);
}

/// Toma o elige la foto y abre la lectura. Cancelar no hace nada.
Future<void> scanReceipt(BuildContext context, {required bool fromCamera}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  String? path;
  try {
    path = await container.read(imagePickerProvider)(fromCamera);
  } on PlatformException {
    if (context.mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
        content: Text('Outflow no tiene permiso para usar la cámara o las fotos. Actívalo en Ajustes del iPhone.'),
      ));
    }
    return;
  }
  if (path == null || !context.mounted) return;
  await Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _ReadingScreen(path: path!),
  ));
}

/// La foto con una línea de escaneo mientras se lee; luego, el resultado.
class _ReadingScreen extends ConsumerStatefulWidget {
  const _ReadingScreen({required this.path});
  final String path;

  @override
  ConsumerState<_ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends ConsumerState<_ReadingScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void initState() {
    super.initState();
    _scan.repeat(reverse: true);
    _read();
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    final now = ref.read(nowProvider);
    final currency = ref.read(walletSettingsRepositoryProvider).read().currency;
    var receipt = const ReceiptData();
    var failed = false;
    try {
      final text = await ref.read(textRecognizerProvider).recognize(widget.path);
      // Sin texto no hay nada que leer: no se pregunta a la IA (podría inventar).
      if (text.trim().isEmpty) {
        failed = true;
      } else {
        receipt = await ref.read(receiptReaderProvider).read(text, now: now, fallbackCurrency: currency);
      }
    } on TextRecognitionFailed {
      failed = true;
    }
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => ReceiptResultScreen(receipt: receipt, readFailed: failed),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    Widget broken(BuildContext _, Object _, StackTrace? _) => const ColoredBox(color: AppColors.inkSecondary);
    final image = kIsWeb
        ? Image.network(widget.path, fit: BoxFit.cover, errorBuilder: broken)
        : Image.file(File(widget.path), fit: BoxFit.cover, errorBuilder: broken);
    return Scaffold(
      backgroundColor: AppColors.ink,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: ClipRSuperellipse(
                  borderRadius: BorderRadius.circular(24),
                  child: LayoutBuilder(
                    builder: (context, c) => Stack(
                      fit: StackFit.expand,
                      children: [
                        image,
                        const ColoredBox(color: Color(0x33000000)),
                        if (!reduced)
                          AnimatedBuilder(
                            animation: _scan,
                            builder: (context, _) => Positioned(
                              left: 0,
                              right: 0,
                              top: (c.maxHeight - 4) * Curves.easeInOut.transform(_scan.value),
                              child: Container(
                                height: 4,
                                decoration: const BoxDecoration(
                                  color: AppColors.accent,
                                  boxShadow: [BoxShadow(color: AppColors.accent, blurRadius: 18, spreadRadius: 2)],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Text('Leyendo ticket…', style: AppType.headline.copyWith(color: AppColors.onAccent)),
            const SizedBox(height: 6),
            Text(
              'La foto se queda en tu iPhone.',
              style: AppType.footnote.copyWith(color: AppColors.onAccent.withValues(alpha: 0.7)),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
