import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/core_providers.dart';
import 'core/motion/app_motion.dart';
import 'core/motion/motion_widgets.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/outflow_mark.dart';
import 'features/account/presentation/lock_screen.dart';
import 'features/account/presentation/session_controller.dart';
import 'features/account/presentation/welcome_screen.dart';
import 'features/notifications/data/charge_answer_inbox.dart';
import 'features/onboarding/presentation/onboarding_flow.dart';
import 'features/wallet/presentation/wallet_providers.dart';
import 'features/notifications/domain/charge_answer.dart';
import 'features/notifications/presentation/notification_providers.dart';
import 'features/subscriptions/presentation/subscription_providers.dart';
import 'features/subscriptions/presentation/screens/dashboard_screen.dart';
import 'features/subscriptions/presentation/screens/subscription_detail_screen.dart';

class OutflowApp extends ConsumerStatefulWidget {
  const OutflowApp({super.key});

  @override
  ConsumerState<OutflowApp> createState() => _OutflowAppState();
}

class _OutflowAppState extends ConsumerState<OutflowApp> {
  final _navigator = GlobalKey<NavigatorState>();
  late final AppLifecycleListener _lifecycle;
  StreamSubscription<String>? _tapSub;
  StreamSubscription<ChargeAnswer>? _answerSub;

  /// Gracia antes de re-bloquear al volver (cambiar de app un momento no pide PIN).
  static const _relockAfter = Duration(seconds: 30);
  DateTime? _hiddenAt;

  /// Portada de privacidad: el multitarea no muestra importes.
  bool _obscured = false;

  /// Notificación tocada mientras la app estaba bloqueada: se abre al desbloquear.
  String? _pendingSubscriptionId;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: () => setState(() => _obscured = true),
      onHide: () => _hiddenAt ??= DateTime.now(),
      onShow: _onReturn,
      onResume: () => setState(() => _obscured = false),
    );

    final notifications = ref.read(notificationServiceProvider);
    _tapSub = notifications.taps.listen(_openFromNotification);
    notifications.launchPayload().then((id) {
      if (id != null) _openFromNotification(id);
    });

    // Botones de "¿tu próximo cobro es el …?": al momento si la app está
    // abierta; los pulsados con la app cerrada esperan en la bandeja.
    final actions = ref.read(subscriptionActionsProvider);
    _answerSub = notifications.answers.listen(actions.applyAnswer);
    _applyQueuedAnswers();
  }

  Future<void> _applyQueuedAnswers() async {
    final actions = ref.read(subscriptionActionsProvider);
    try {
      for (final a in await const ChargeAnswerInbox().drain()) {
        await actions.applyAnswer(a);
      }
    } catch (e) {
      debugPrint('No se pudieron aplicar las respuestas pendientes: $e');
    }
  }

  void _onReturn() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // "Hoy" puede haber cambiado: recalcula fechas relativas y reprograma avisos.
    ref.invalidate(nowProvider);
    _applyQueuedAnswers();
    if (hiddenAt != null && DateTime.now().difference(hiddenAt) > _relockAfter) {
      ref.read(sessionControllerProvider.notifier).lock();
    }
  }

  void _openFromNotification(String subscriptionId) {
    if (ref.read(sessionControllerProvider) is Ready) {
      _navigator.currentState?.push(MaterialPageRoute<void>(
        builder: (_) => SubscriptionDetailScreen(subscriptionId: subscriptionId),
      ));
    } else {
      _pendingSubscriptionId = subscriptionId;
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _tapSub?.cancel();
    _answerSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene los avisos programados sincronizados con los datos.
    ref.watch(reminderSyncProvider);

    // Los cobros de suscripciones se reflejan como gastos de la wallet.
    ref.watch(chargeMovementSyncProvider);

    ref.listen(sessionControllerProvider, (prev, next) {
      if (next is Ready && _pendingSubscriptionId != null) {
        final id = _pendingSubscriptionId!;
        _pendingSubscriptionId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openFromNotification(id));
      }
    });

    final session = ref.watch(sessionControllerProvider);
    final locked = session is! Ready;

    return MaterialApp(
      title: 'Outflow',
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigator,
      theme: AppTheme.light(),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const DashboardScreen(),
      builder: (context, child) => Stack(
        children: [
          // El contenido queda inerte e invisible para lectores de pantalla mientras está bloqueado.
          ExcludeSemantics(
            excluding: locked,
            child: IgnorePointer(
              ignoring: locked,
              // Las entradas esperan al desbloqueo para revelarse a la vista.
              child: EntranceGate(open: !locked, child: child!),
            ),
          ),
          _LockLayer(session: session),
          if (_obscured && !locked) const _PrivacyCover(),
        ],
      ),
    );
  }
}

/// Al desbloquear, la pantalla de bloqueo se hunde y se desvanece (como una
/// hoja que baja) mientras el contenido entra por escalones; al re-bloquear
/// sube de la misma forma.
class _LockLayer extends StatelessWidget {
  const _LockLayer({required this.session});
  final SessionState session;

  Widget? _screen() => switch (session) {
        SessionLoading() => const ColoredBox(color: AppColors.background),
        SignedOut() => const WelcomeScreen(),
        final Locked s => LockScreen(state: s),
        final NeedsOnboarding s => OnboardingFlow(state: s),
        Ready() => null,
      };

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? AppMotion.short : const Duration(milliseconds: 460),
      switchInCurve: AppMotion.ease,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduced) return fade;
        return SlideTransition(
          position: Tween(begin: const Offset(0, 0.06), end: Offset.zero).animate(animation),
          child: fade,
        );
      },
      child: switch (_screen()) {
        // Navigator propio: las pantallas de entrada pueden mostrar diálogos.
        // Sin HeroController: el de MaterialApp ya lo usa el Navigator principal.
        final Widget screen => HeroControllerScope.none(
            // Una clave por tipo de pantalla: cambiar de bienvenida a
            // configuración o a bloqueo también se anima.
            key: ValueKey(session.runtimeType),
            child: Navigator(
              onGenerateRoute: (_) => PageRouteBuilder<void>(pageBuilder: (_, _, _) => screen),
            ),
          ),
        null => const SizedBox.shrink(key: ValueKey('open')),
      },
    );
  }
}

class _PrivacyCover extends StatelessWidget {
  const _PrivacyCover();

  @override
  Widget build(BuildContext context) => const Positioned.fill(
        child: ColoredBox(
          color: AppColors.background,
          child: Center(child: OutflowMark(size: 64)),
        ),
      );
}
