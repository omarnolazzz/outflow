import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion/app_motion.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// Control segmentado monocromo: el indicador se desliza al segmento elegido.
class NotionSegmented<T> extends StatelessWidget {
  const NotionSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final keys = options.keys.toList();
    final index = keys.indexOf(value);

    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, c) {
          final w = c.maxWidth / keys.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.medium,
                curve: AppMotion.ease,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: AppColors.border),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final k in keys)
                    Expanded(
                      child: Semantics(
                        selected: k == value,
                        button: true,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (k == value) return;
                            HapticFeedback.selectionClick();
                            onChanged(k);
                          },
                          child: Center(
                            child: Text(
                              options[k]!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.caption.copyWith(
                                fontWeight: FontWeight.w500,
                                color: k == value ? AppColors.ink : AppColors.inkSecondary,
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
