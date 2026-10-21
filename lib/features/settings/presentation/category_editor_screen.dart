import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';

import '../../../core/motion/motion_widgets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/pressable.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../core/widgets/segmented_control.dart';
import '../../../core/widgets/sheet_scaffold.dart';
import '../../../core/widgets/status_pill.dart';
import '../../../core/widgets/surface_card.dart';
import '../../wallet/domain/category.dart';
import '../../wallet/domain/movement.dart';
import '../../wallet/presentation/wallet_providers.dart';
import '../../wallet/presentation/widgets/category_icon.dart';

/// Colores suaves disponibles para categorías.
const _palette = [
  0xFFFF9F0A, 0xFF34C759, 0xFF0A84FF, 0xFFAC8E68, 0xFFFFCC00, 0xFFFF375F,
  0xFFBF5AF2, 0xFFFF6482, 0xFF5E5CE6, 0xFF64D2FF, 0xFF30B0C7, 0xFF8E8E93,
];

/// Lista de categorías: tocar una la edita; "+" crea una nueva.
class CategoryEditorScreen extends ConsumerStatefulWidget {
  const CategoryEditorScreen({super.key});

  @override
  ConsumerState<CategoryEditorScreen> createState() => _CategoryEditorScreenState();
}

class _CategoryEditorScreenState extends ConsumerState<CategoryEditorScreen> {
  MovementKind _kind = MovementKind.expense;

  Future<void> _edit(Category? c) async {
    final result = await showModalBottomSheet<Category>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategorySheet(category: c, kind: _kind),
    );
    if (result != null) await ref.read(categoryRepositoryProvider).save(result);
  }

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(categoriesProvider).value ?? const <Category>[];
    final list = all.where((c) => c.kind == _kind).toList();
    return SheetScaffold(
      title: 'Categorías',
      trailing: CircleIconButton(icon: LucideIcons.plus, label: 'Nueva categoría', onTap: () => _edit(null)),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          SegmentedControl<MovementKind>(
            values: MovementKind.values,
            selected: _kind,
            label: (k) => k == MovementKind.expense ? 'Gastos' : 'Ingresos',
            onChanged: (k) => setState(() => _kind = k),
          ),
          const SizedBox(height: 14),
          SurfaceCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                for (final (i, c) in list.indexed)
                  Entrance(
                    key: ValueKey(c.id),
                    index: i,
                    child: Pressable(
                      onTap: c.reserved ? null : () => _edit(c),
                      borderRadius: BorderRadius.circular(14),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        child: Row(
                          children: [
                            CategoryBadge(category: c, size: 36),
                            const SizedBox(width: 12),
                            Expanded(child: Text(c.name, style: AppType.body)),
                            if (c.reserved)
                              const StatusPill('Automática')
                            else
                              const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.inkTertiary),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({required this.category, required this.kind});
  final Category? category;
  final MovementKind kind;

  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final _name = TextEditingController(text: widget.category?.name ?? '');
  late String _icon = widget.category?.icon ?? 'circle';
  late int _color = widget.category?.color ?? _palette.first;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    await ref.read(categoryRepositoryProvider).delete(widget.category!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final preview = Category(id: 'p', name: _name.text, kind: widget.kind, icon: _icon, color: _color);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CategoryBadge(category: preview, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _name,
                    autofocus: widget.category == null,
                    style: AppType.title2,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(hintText: 'Nombre'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _color = c);
                    },
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Color(c),
                        shape: BoxShape.circle,
                        border: Border.all(color: c == _color ? AppColors.ink : Colors.transparent, width: 2.5),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 168,
              child: GridView.count(
                crossAxisCount: 7,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [
                  for (final e in kCategoryIcons.entries)
                    Pressable(
                      onTap: () => setState(() => _icon = e.key),
                      highlight: false,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        decoration: ShapeDecoration(
                          color: e.key == _icon ? Color(_color).withValues(alpha: 0.18) : AppColors.fill,
                          shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Icon(e.value, size: 20, color: e.key == _icon ? Color(_color) : AppColors.inkSecondary),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            PrimaryButton(
              label: 'Guardar',
              onTap: _name.text.trim().isEmpty
                  ? null
                  : () => Navigator.pop(
                        context,
                        widget.category?.copyWith(name: _name.text.trim(), icon: _icon, color: _color) ??
                            Category(
                              id: const Uuid().v4(),
                              name: _name.text.trim(),
                              kind: widget.kind,
                              icon: _icon,
                              color: _color,
                            ),
                      ),
            ),
            if (widget.category != null)
              Center(
                child: TextButton(
                  onPressed: _delete,
                  child: const Text('Eliminar categoría', style: TextStyle(color: AppColors.danger)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
