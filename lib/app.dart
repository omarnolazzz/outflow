import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/di/core_providers.dart';
import 'core/motion/app_motion.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/outflow_mark.dart';
import 'features/auth/presentation/lock_controller.dart';
import 'features/auth/presentation/lock_screen.dart';
import 'features/notifications/presentation/notification_providers.dart';
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
  }

  void _onReturn() {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    // "Hoy" puede haber cambiado: recalcula fechas relativas y reprograma avisos.
    ref.invalidate(nowProvider);
    if (hiddenAt != null && DateTime.now().difference(hiddenAt) > _relockAfter) {
      ref.read(lockControllerProvider.notifier).lock();
    }
  }

  void _openFromNotification(String subscriptionId) {
    if (ref.read(lockControllerProvider) is LockUnlocked) {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Mantiene los avisos programados sincronizados con los datos.
    ref.watch(reminderSyncProvider);

    ref.listen(lockControllerProvider, (prev, next) {
      if (next is LockUnlocked && _pendingSubscriptionId != null) {
        final id = _pendingSubscriptionId!;
        _pendingSubscriptionId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) => _openFromNotification(id));
      }
    });

    final lock = ref.watch(lockControllerProvider);
    final locked = lock is! LockUnlocked;

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
            child: IgnorePointer(ignoring: locked, child: child),
          ),
          _LockLayer(locked: locked),
          if (_obscured && !locked) const _PrivacyCover(),
        ],
      ),
    );
  }
}

/// La pantalla de bloqueo se "levanta" al desbloquear: fundido + leve
/// escala hacia el usuario, como un material que se retira.
class _LockLayer extends StatelessWidget {
  const _LockLayer({required this.locked});
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final reduced = AppMotion.reduced(context);
    return AnimatedSwitcher(
      duration: reduced ? AppMotion.short : const Duration(milliseconds: 380),
      switchInCurve: AppMotion.ease,
      switchOutCurve: AppMotion.ease,
      transitionBuilder: (child, animation) {
        final fade = FadeTransition(opacity: animation, child: child);
        if (reduced) return fade;
        return ScaleTransition(
          scale: Tween(begin: 1.04, end: 1.0).animate(animation),
          child: fade,
        );
      },
      child: locked
          // Navigator propio: la pantalla de bloqueo puede mostrar diálogos.
          ? Navigator(
              key: const ValueKey('lock'),
              onGenerateRoute: (_) => PageRouteBuilder<void>(
                pageBuilder: (_, _, _) => const LockScreen(),
              ),
            )
          : const SizedBox.shrink(key: ValueKey('open')),
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
