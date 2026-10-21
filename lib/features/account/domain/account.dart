import 'package:meta/meta.dart';

/// La cuenta de Google con la que se entra en Outflow.
@immutable
class Account {
  const Account({required this.uid, required this.email, required this.displayName, this.photoUrl});

  final String uid;
  final String email;
  final String displayName;
  final String? photoUrl;

  /// "Gabriel" de "Gabriel Nolazco" (para el saludo).
  String get firstName {
    final name = displayName.trim();
    if (name.isEmpty) return email.split('@').first;
    return name.split(RegExp(r'\s+')).first;
  }
}
