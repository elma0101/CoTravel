import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/traveler_action_target.dart';

enum _TravelerAction { viewProfile, message }

Future<void> showTravelerActions(
  BuildContext context, {
  required TravelerActionTarget target,
  bool openedFromConversation = false,
}) async {
  final action = await showModalBottomSheet<_TravelerAction>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (context) => _TravelerActionSheet(
      target: target,
      openedFromConversation: openedFromConversation,
    ),
  );
  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case _TravelerAction.viewProfile:
      context.push(
        AppRoutes.memberProfile(
          target.userId,
          tripId: target.tripId,
          conversationId: target.conversationId,
          openedFromConversation: openedFromConversation,
        ),
        extra: target,
      );
    case _TravelerAction.message:
      final conversationId = target.conversationId;
      if (conversationId != null && !openedFromConversation) {
        context.push(AppRoutes.conversation(conversationId));
      }
  }
}

class _TravelerActionSheet extends ConsumerWidget {
  const _TravelerActionSheet({
    required this.target,
    required this.openedFromConversation,
  });

  final TravelerActionTarget target;
  final bool openedFromConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final safety = ref.watch(safetyControllerProvider);
    final currentUserId = ref.watch(appAuthStateProvider).profile?.id;
    return ListenableBuilder(
      listenable: safety,
      builder: (context, child) {
        final isBlocked = safety.isBlocked(target.userId);
        final isSelf = currentUserId == target.userId;
        final canMessage = target.conversationId != null && !isBlocked;
        final messageSubtitle = switch ((isBlocked, canMessage)) {
          (true, _) => 'Unblock this traveler before messaging.',
          (false, true) when openedFromConversation =>
            'Return to your shared trip conversation.',
          (false, true) => 'Open your shared trip conversation.',
          _ => 'Available after your place on this trip is confirmed.',
        };

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 29,
                      backgroundColor: AppColors.greenSoft,
                      foregroundImage: target.avatarUrl == null
                          ? null
                          : NetworkImage(target.avatarUrl!),
                      child: target.avatarUrl == null
                          ? Text(
                              target.initials,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: AppColors.green,
                                    fontWeight: FontWeight.w800,
                                  ),
                            )
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  target.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                              ),
                              if (target.isVerified) ...[
                                const SizedBox(width: AppSpacing.xs),
                                const Icon(
                                  Icons.verified_rounded,
                                  size: 18,
                                  color: AppColors.green,
                                ),
                              ],
                            ],
                          ),
                          Text(
                            target.homeCity ?? 'CoTravel member',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                _ActionTile(
                  key: ValueKey('view-profile-${target.userId}'),
                  icon: Icons.person_outline_rounded,
                  title: isSelf ? 'View your profile' : 'View profile',
                  subtitle: isBlocked
                      ? 'Profile hidden while this traveler is blocked.'
                      : 'See their bio, travel style, and languages.',
                  onTap: isBlocked
                      ? null
                      : () => Navigator.of(
                          context,
                        ).pop(_TravelerAction.viewProfile),
                ),
                const SizedBox(height: AppSpacing.sm),
                _ActionTile(
                  key: ValueKey('message-user-${target.userId}'),
                  icon: Icons.chat_bubble_outline_rounded,
                  title: openedFromConversation
                      ? 'Back to trip chat'
                      : 'Message',
                  subtitle: messageSubtitle,
                  onTap: canMessage
                      ? () {
                          Navigator.of(context).pop(_TravelerAction.message);
                        }
                      : null,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap == null ? AppColors.canvas : AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: onTap == null
                      ? AppColors.border.withValues(alpha: 0.45)
                      : AppColors.greenSoft,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: onTap == null ? AppColors.muted : AppColors.green,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: onTap == null ? AppColors.muted : AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Icon(
                onTap == null
                    ? Icons.lock_outline_rounded
                    : Icons.chevron_right_rounded,
                color: AppColors.muted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
