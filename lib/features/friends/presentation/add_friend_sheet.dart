import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../data/social_repository.dart';
import 'friends_providers.dart';

/// Hoja para invitar a alguien por su correo de Google.
Future<void> showAddFriendSheet(BuildContext context) =>
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const AddFriendSheet(),
    ));

class AddFriendSheet extends ConsumerStatefulWidget {
  const AddFriendSheet({super.key});

  @override
  ConsumerState<AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<AddFriendSheet> {
  final _email = TextEditingController();
  bool _sending = false;
  String? _message;
  bool _ok = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  static String _text(AddFriendResult r) => switch (r) {
        AddFriendResult.sent => 'Solicitud enviada.',
        AddFriendResult.accepted => 'Ya te había invitado: ahora son amigos.',
        AddFriendResult.notOnOutflow => 'Esa persona aún no usa Outflow. Pídele que la instale y entre con Google.',
        AddFriendResult.self => 'Ese es tu correo.',
        AddFriendResult.alreadyFriends => 'Ya son amigos.',
        AddFriendResult.alreadySent => 'Ya le enviaste una solicitud.',
        AddFriendResult.offline => 'Sin conexión',
      };

  Future<void> _send() async {
    final email = _email.text.trim();
    if (email.isEmpty || _sending) return;
    setState(() => _sending = true);
    String message;
    var ok = false;
    try {
      // Se espera: devuelve el resultado (y `offline` por sí mismo sin red).
      final r = await ref.read(socialRepositoryProvider).addFriend(email);
      message = _text(r);
      ok = r == AddFriendResult.sent || r == AddFriendResult.accepted;
    } catch (e) {
      debugPrint('No se pudo añadir al amigo: $e');
      message = 'No se pudo enviar la solicitud. Inténtalo de nuevo.';
    }
    if (!mounted) return;
    setState(() {
      _sending = false;
      _message = message;
      _ok = ok;
      if (ok) _email.clear();
    });
  }

  @override
  Widget build(BuildContext context) => SheetScaffold(
        title: 'Añadir amigo',
        closeIcon: true,
        bottom: PrimaryButton(label: 'Enviar solicitud', loading: _sending, onTap: _send),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          children: [
            TextField(
              controller: _email,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.send,
              autocorrect: false,
              onSubmitted: (_) => _send(),
              style: AppType.body,
              decoration: const InputDecoration(hintText: 'Correo de Google de tu amigo'),
            ),
            if (_message != null) ...[
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  _message!,
                  style: AppType.subhead.copyWith(color: _ok ? AppColors.accent : AppColors.inkSecondary),
                ),
              ),
            ],
          ],
        ),
      );
}
