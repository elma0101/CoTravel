import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../l10n/app_strings.dart';

/// The animated bar at the top of a step-by-step flow.
class FlowProgressBar extends StatelessWidget {
  const FlowProgressBar({required this.step, required this.count, super.key});

  final int step;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: tr('Step {number} of {count}', {
        'number': step + 1,
        'count': count,
      }),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: (step + 1) / count),
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: value,
              minHeight: 8,
              color: AppColors.green,
              backgroundColor: AppColors.greenSoft,
            ),
          );
        },
      ),
    );
  }
}

/// One full-screen question: a big title, a hint, and what answers it.
class FlowStep extends StatelessWidget {
  const FlowStep({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.xs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.xl),
        ...children,
      ],
    );
  }
}

/// A large, tappable choice that fills in when selected.
class ChoicePill extends StatelessWidget {
  const ChoicePill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    super.key,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : AppColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? AppColors.green : AppColors.border,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null || selected) ...[
                  Icon(
                    selected ? Icons.check_rounded : icon,
                    size: 18,
                    color: selected ? Colors.white : AppColors.ink,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                ],
                Flexible(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
