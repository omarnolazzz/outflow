import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/glass.dart';
import 'glass_tab_bar.dart';
import 'quick_add_menu.dart';

export 'glass_tab_bar.dart' show AppTab;
export 'quick_add_menu.dart' show QuickAction;

/// Espacio que las páginas deben dejar abajo para no quedar bajo la barra.
double shellBottomInset(BuildContext context) => kTabBarHeight + 24 + MediaQuery.paddingOf(context).bottom;

/// Permite a una página cambiar de pestaña ("Ver todos" → Movimientos).
class ShellScope extends InheritedWidget {
  const ShellScope({super.key, required this.select, required this.quickAdd, required super.child});
  final ValueChanged<AppTab> select;

  /// Mismas acciones que el botón "+" (p. ej. "Registrar ingreso" desde Inicio).
  final ValueChanged<QuickAction> quickAdd;

  static ShellScope? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => false;
}

/// Estructura principal: 5 pestañas, cada una con su propio Navigator (conserva
/// su pila y su scroll), barra de cristal flotante y botón "+".
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.pages, required this.onQuickAdd});

  final Map<AppTab, WidgetBuilder> pages;

  /// Recibe la acción elegida en el menú "+" y el contexto del navegador raíz.
  final void Function(QuickAction action) onQuickAdd;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  AppTab _tab = AppTab.home;
  bool _menu = false;
  final _navigators = {for (final t in AppTab.values) t: GlobalKey<NavigatorState>()};
  final _scrolls = {for (final t in AppTab.values) t: ScrollController()};

  @override
  void dispose() {
    for (final c in _scrolls.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _select(AppTab t) {
    if (t == _tab) {
      // Volver a tocar la pestaña activa: a su raíz, y si ya está, arriba del todo.
      final nav = _navigators[t]!.currentState;
      if (nav != null && nav.canPop()) {
        nav.popUntil((r) => r.isFirst);
      } else {
        final c = _scrolls[t]!;
        if (c.hasClients) c.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
      }
      return;
    }
    setState(() {
      _tab = t;
      _menu = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.paddingOf(context).bottom;
    final barBottom = (bottomSafe > 0 ? bottomSafe : 12.0) + 4;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_menu) return setState(() => _menu = false);
        _navigators[_tab]!.currentState?.maybePop();
      },
      child: ShellScope(
        select: _select,
        quickAdd: widget.onQuickAdd,
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Stack(
            children: [
              IndexedStack(
                index: _tab.index,
                children: [
                  for (final t in AppTab.values)
                    // Las pestañas ocultas no se pintan ni reciben toques.
                    TickerMode(
                      enabled: t == _tab,
                      child: PrimaryScrollController(
                        controller: _scrolls[t]!,
                        child: Navigator(
                          key: _navigators[t],
                          onGenerateRoute: (settings) => MaterialPageRoute<void>(
                            settings: settings,
                            builder: widget.pages[t]!,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Positioned.fill(
                child: QuickAddOverlay(
                  open: _menu,
                  bottom: barBottom + kTabBarHeight,
                  onClose: () => setState(() => _menu = false),
                  onAction: (a) {
                    setState(() => _menu = false);
                    widget.onQuickAdd(a);
                  },
                ),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: barBottom,
                child: BarGlassLayer(
                  child: Row(
                    children: [
                      Expanded(child: GlassTabBar(current: _tab, onSelect: _select)),
                      const SizedBox(width: 10),
                      QuickAddButton(open: _menu, onTap: () => setState(() => _menu = !_menu)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
