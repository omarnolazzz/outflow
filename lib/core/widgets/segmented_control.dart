import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Control segmentado estilo iOS: una píldora blanca se desliza bajo la opción elegida.
class SegmentedControl<T> extends StatelessWidget {
  const SegmentedControl({super.key, required this.values, required this.selected, required this.label, required this.onChanged});

  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final index = values.indexOf(selected);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: ShapeDecoration(color: AppColors.fill, shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(12))),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / values.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.reduced(context) ? Duration.zero : const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: AppColors.surface,
                    shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(9)),
                    shadows: const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final v in values)
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: v == selected,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (v == selected) return;
                            HapticFeedback.selectionClick();
                            onChanged(v);
                          },
                          child: Center(
                            child: Text(
                              label(v),
                              style: AppType.subhead.copyWith(
                                color: AppColors.ink,
                                fontWeight: v == selected ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
