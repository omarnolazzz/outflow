import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../core/motion/app_motion.dart';
import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/outflow_mark.dart';
import '../../../core/widgets/pressable.dart';
import '../domain/auth_repository.dart';
import 'lock_controller.dart';

const _pinLength = 6;

/// Pantalla de bloqueo y de creación de PIN.
class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

enum _Step { enter, create, confirm }

class _LockScreenState extends ConsumerState<LockScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  String _pin = '';
  String? _firstPin;
  String? _message;
  bool _busy = false;
  Timer? _lockoutTicker;
  bool _autoBioTried = false;

  _Step get _step {
    final s = ref.read(lockControllerProvider);
    if (s is LockNeedsSetup) return _firstPin == null ? _Step.create : _Step.confirm;
    return _Step.enter;
  }

  @override
  void dispose() {
    _shake.dispose();
    _lockoutTicker?.cancel();
    super.dispose();
  }

  void _tryAutoBiometrics(AppLockState s) {
    if (_autoBioTried || s is! LockLocked || s.biometricLabel == null) return;
    _autoBioTried = true;
    // Tras el primer frame, para que la pantalla ya sea visible bajo el prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) => _biometrics());
  }

  Future<void> _biometrics() async {
    await ref.read(lockControllerProvider.notifier).unlockWithBiometrics();
  }

  void _press(String digit) {
    if (_busy || _pin.length >= _pinLength || _isLockedOut) return;
    HapticFeedback.lightImpact();
    setState(() {
      _pin += digit;
      _message = null;
    });
    if (_pin.length == _pinLength) _complete();
  }

  void _backspace() {
    if (_pin.isEmpty || _busy) return;
    HapticFeedback.selectionClick();
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _complete() async {
    final controller = ref.read(lockControllerProvider.notifier);
    switch (_step) {
      case _Step.create:
        setState(() {
          _firstPin = _pin;
          _pin = '';
        });
      case _Step.confirm:
        if (_pin != _firstPin) {
          _fail('Los PIN no coinciden. Empieza de nuevo.');
          setState(() => _firstPin = null);
          return;
        }
        final s = ref.read(lockControllerProvider);
        final bio = s is LockNeedsSetup ? s.biometricLabel : null;
        final enableBio = bio != null && await _askBiometrics(bio);
        setState(() => _busy = true);
        await controller.createPin(_pin, enableBiometrics: enableBio);
      case _Step.enter:
        setState(() => _busy = true);
        final result = await controller.submitPin(_pin);
        if (!mounted) return;
        setState(() => _busy = false);
        switch (result) {
          case PinAccepted():
            HapticFeedback.mediumImpact();
          case PinRejected(:final attemptsLeft):
            _fail(attemptsLeft == 1 ? 'PIN incorrecto. Te queda 1 intento.' : 'PIN incorrecto.');
          case PinLockedOut():
            _fail(null);
            _startLockoutTicker();
        }
    }
  }

  Future<bool> _askBiometrics(String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text('¿Desbloquear con $label?', style: AppType.headline),
        content: Text(
          'Podrás seguir usando tu PIN. Se puede cambiar en Ajustes.',
          style: AppType.body.copyWith(color: AppColors.inkSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Ahora no', style: AppType.bodyStrong.copyWith(color: AppColors.inkSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Activar', style: AppType.bodyStrong),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _fail(String? message) {
    HapticFeedback.heavyImpact();
    setState(() {
      _pin = '';
      _message = message;
    });
    if (!AppMotion.reduced(context)) _shake.forward(from: 0);
  }

  bool get _isLockedOut {
    final s = ref.read(lockControllerProvider);
    return s is LockLocked && s.lockedOutUntil != null && s.lockedOutUntil!.isAfter(DateTime.now());
  }

  void _startLockoutTicker() {
    _lockoutTicker?.cancel();
    _lockoutTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      setState(() {});
      if (!_isLockedOut) t.cancel();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(lockControllerProvider);
    _tryAutoBiometrics(state);
    if (state is LockLocked && _isLockedOut && _lockoutTicker == null) _startLockoutTicker();

    final (title, subtitle) = switch (_step) {
      _Step.create => ('Crea tu PIN', 'Protege tus datos financieros en este dispositivo.'),
      _Step.confirm => ('Confirma tu PIN', 'Escríbelo una vez más.'),
      _Step.enter => ('Outflow', 'Introduce tu PIN para continuar.'),
    };

    final lockoutLeft = state is LockLocked && state.lockedOutUntil != null
        ? state.lockedOutUntil!.difference(DateTime.now()).inSeconds
        : 0;
    final message = lockoutLeft > 0 ? 'Demasiados intentos. Espera $lockoutLeft s.' : _message;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: state is LockLoading
            ? const SizedBox.shrink()
            : Column(
                children: [
                  const Spacer(flex: 3),
                  const Entrance(
                    scale: 0.5,
                    offset: Offset.zero,
                    duration: Duration(milliseconds: 650),
                    curve: Curves.easeOutBack,
                    child: OutflowMark(size: 56),
                  ),
                  const SizedBox(height: 20),
                  Entrance(
                    index: 2,
                    child: AnimatedSwitcher(
                      duration: AppMotion.medium,
                      switchInCurve: AppMotion.ease,
                      switchOutCurve: AppMotion.ease,
                      // Paso a paso (crear → confirmar): el texto nuevo sube, el viejo se va.
                      transitionBuilder: (child, a) => FadeTransition(
                        opacity: a,
                        child: SlideTransition(
                          position: Tween(begin: const Offset(0, 0.25), end: Offset.zero).animate(a),
                          child: child,
                        ),
                      ),
                      child: Column(
                        key: ValueKey(_step),
                        children: [
                          Text(title, style: AppType.title),
                          const SizedBox(height: 6),
                          Text(subtitle, style: AppType.caption, textAlign: TextAlign.center),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Entrance(
                    index: 3,
                    child: AnimatedBuilder(
                      animation: _shake,
                      builder: (context, child) {
                        // Oscilación amortiguada: se lee como "no", no como error del sistema.
                        final t = _shake.value;
                        final dx = math.sin(t * math.pi * 6) * (1 - t) * 12;
                        return Transform.translate(offset: Offset(dx, 0), child: child);
                      },
                      child: _PinDots(filled: _pin.length, error: _message != null),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 20,
                    child: AnimatedOpacity(
                      opacity: message == null ? 0 : 1,
                      duration: AppMotion.short,
                      child: Text(message ?? '', style: AppType.caption.copyWith(color: AppColors.danger)),
                    ),
                  ),
                  const Spacer(flex: 2),
                  _Keypad(
                    onDigit: _press,
                    onBackspace: _backspace,
                    onBiometric: state is LockLocked && state.biometricLabel != null ? _biometrics : null,
                    biometricIsFace: state is LockLocked && state.biometricLabel == 'Face ID',
                  ),
                  const SizedBox(height: 24),
                ],
              ),
      ),
    );
  }
}

class _PinDots extends StatelessWidget {
  const _PinDots({required this.filled, required this.error});
  final int filled;
  final bool error;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$filled de $_pinLength dígitos',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [for (var i = 0; i < _pinLength; i++) _PinDot(filled: i < filled, error: error)],
      ),
    );
  }
}

/// Punto del PIN: al rellenarse "late" con un resorte (crece y vuelve),
/// y tras un error se tiñe un instante del color de peligro.
class _PinDot extends StatefulWidget {
  const _PinDot({required this.filled, required this.error});
  final bool filled;
  final bool error;

  @override
  State<_PinDot> createState() => _PinDotState();
}

class _PinDotState extends State<_PinDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController.unbounded(vsync: this, value: 0);

  @override
  void didUpdateWidget(_PinDot old) {
    super.didUpdateWidget(old);
    if (widget.filled && !old.filled && !AppMotion.reduced(context)) {
      // Impulso con velocidad inicial: sube y el resorte lo devuelve a reposo.
      _pop.animateWith(SpringSimulation(AppMotion.momentum, 0, 0, 9));
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.filled ? AppColors.ink : (widget.error ? AppColors.danger : AppColors.border);
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) => Transform.scale(scale: 1 + _pop.value * 0.45, child: child),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: AppMotion.ease,
        margin: const EdgeInsets.symmetric(horizontal: 7),
        width: 12,
        height: 12,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.filled ? AppColors.ink : AppColors.background,
          border: Border.all(color: color, width: 1.5),
        ),
      ),
    );
  }
}

class _Keypad extends StatelessWidget {
  const _Keypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onBiometric,
    required this.biometricIsFace,
  });

  final ValueChanged<String> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback? onBiometric;
  final bool biometricIsFace;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback? onTap, String label) => SizedBox(
      width: 84,
      height: 64,
      child: Pressable(
        onTap: onTap,
        scale: 0.92,
        borderRadius: BorderRadius.circular(32),
        semanticLabel: label,
        child: Center(child: child),
      ),
    );

    Widget digit(String d) => key(
      Text(d, style: AppType.title.copyWith(fontSize: 26, fontWeight: FontWeight.w400)),
      () => onDigit(d),
      d,
    );

    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];

    // El teclado sube fila a fila después del título y los puntos.
    Widget enter(int i, Widget row) => Entrance(
      index: 4 + i,
      step: const Duration(milliseconds: 55),
      offset: const Offset(0, 24),
      child: row,
    );

    return Column(
      children: [
        for (final (i, row) in rows.indexed)
          enter(i, Row(mainAxisAlignment: MainAxisAlignment.center, children: row.map(digit).toList())),
        enter(
          3,
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              onBiometric == null
                  ? const SizedBox(width: 84, height: 64)
                  : key(
                      Icon(
                        biometricIsFace ? LucideIcons.scanFace : LucideIcons.fingerprint,
                        size: 24,
                        color: AppColors.ink,
                      ),
                      onBiometric,
                      'Desbloquear con biometría',
                    ),
              digit('0'),
              key(
                const Icon(LucideIcons.delete, size: 22, color: AppColors.inkSecondary),
                onBackspace,
                'Borrar',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
