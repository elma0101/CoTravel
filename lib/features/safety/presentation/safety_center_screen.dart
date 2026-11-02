import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../application/safety_controller.dart';
import '../domain/safety_models.dart';

class SafetyCenterScreen extends ConsumerWidget {
  const SafetyCenterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(safetyControllerProvider);
    return Scaffold(
      appBar: AppBar(title: Text(tr('Safety Center'))),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          if (controller.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (controller.errorMessage != null &&
              controller.reports.isEmpty &&
              controller.blockedUsers.isEmpty) {
            return _SafetyLoadError(onRetry: controller.load);
          }
          return RefreshIndicator(
            onRefresh: controller.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  tr('Travel should feel safe and informed.'),
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  tr(
                    'Reports are reviewed by a person. Blocking is immediate and private.',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.lg),
                const _CommunityStandards(),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  tr('Blocked people'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (controller.blockedUsers.isEmpty)
                  _CompactEmpty(
                    icon: Icons.person_outline_rounded,
                    text: tr('You have not blocked anyone.'),
                  )
                else
                  ...controller.blockedUsers.map(
                    (user) => _BlockedUserTile(
                      user: user,
                      isUpdating: controller.isSubmitting,
                      onUnblock: () => _unblock(context, controller, user),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  tr('Your reports'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (controller.reports.isEmpty)
                  _CompactEmpty(
                    icon: Icons.flag_outlined,
                    text: tr('You have not submitted a report.'),
                  )
                else
                  ...controller.reports.map(_ReportCard.new),
                const SizedBox(height: AppSpacing.xl),
                Text(
                  tr(
                    'CoTravel is not an emergency service. Contact local emergency services when anyone is in immediate danger.',
                  ),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _unblock(
    BuildContext context,
    SafetyController controller,
    BlockedUser user,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          tr('Unblock {displayName}?', {'displayName': user.displayName}),
        ),
        content: Text(
          tr('Their published trips may appear in discovery again.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: ValueKey('confirm-unblock-${user.userId}'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Unblock')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    try {
      await controller.unblock(user.userId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr('{displayName} was unblocked.', {
                'displayName': user.displayName,
              }),
            ),
          ),
        );
      }
    } on Object {
      // The controller exposes the readable failure on the screen.
    }
  }
}

class _CommunityStandards extends StatelessWidget {
  const _CommunityStandards();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield_outlined, color: AppColors.green),
              SizedBox(width: AppSpacing.sm),
              Text(
                tr('Community standard'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          SizedBox(height: AppSpacing.sm),
          Text(tr('• Be honest about identity, itinerary, and shared costs.')),
          SizedBox(height: AppSpacing.xs),
          Text(tr('• Respect boundaries and never pressure another traveler.')),
          SizedBox(height: AppSpacing.xs),
          Text(tr('• Keep coordination in the confirmed group conversation.')),
        ],
      ),
    );
  }
}

class _BlockedUserTile extends StatelessWidget {
  const _BlockedUserTile({
    required this.user,
    required this.isUpdating,
    required this.onUnblock,
  });

  final BlockedUser user;
  final bool isUpdating;
  final VoidCallback onUnblock;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: AppColors.surface,
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: AppColors.terracottaSoft,
          foregroundColor: AppColors.terracotta,
          child: Icon(Icons.block_rounded),
        ),
        title: Text(user.displayName),
        subtitle: Text(tr('Trips hidden and new requests prevented')),
        trailing: TextButton(
          key: ValueKey('unblock-${user.userId}'),
          onPressed: isUpdating ? null : onUnblock,
          child: Text(tr('Unblock')),
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard(this.report);

  final SafetyReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  report.subjectName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _StatusChip(status: report.status),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(tr(report.reason.label)),
          if (report.tripTitle != null)
            Text(
              report.tripTitle!,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          const SizedBox(height: AppSpacing.sm),
          Text(report.details, maxLines: 3, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final SafetyReportStatus status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: status == SafetyReportStatus.resolved
            ? AppColors.greenSoft
            : AppColors.terracottaSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        tr(status.label),
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _SafetyLoadError extends StatelessWidget {
  const _SafetyLoadError({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.shield_outlined,
      title: tr('Safety Center unavailable'),
      message: tr('Your safety settings could not be loaded.'),
      action: TextButton(onPressed: onRetry, child: Text(tr('Try again'))),
    );
  }
}
