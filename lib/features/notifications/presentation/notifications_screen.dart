import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../domain/app_notification.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  void _open(BuildContext context, WidgetRef ref, AppNotification item) {
    ref.read(notificationControllerProvider).markRead(item);
    final target = AppRoutes.notificationTarget(item.kind, item.tripId);
    if (target != null) {
      context.push(target);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(notificationControllerProvider);

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(tr('Notifications')),
            actions: [
              if (controller.unreadCount > 0)
                TextButton(
                  key: const ValueKey('mark-all-notifications-read'),
                  onPressed: controller.markAllRead,
                  child: Text(tr('Mark all read')),
                ),
            ],
          ),
          body: SafeArea(child: _body(context, ref)),
        );
      },
    );
  }

  Widget _body(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(notificationControllerProvider);
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.errorMessage != null) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: tr('Notifications are unavailable'),
        message: controller.errorMessage!,
      );
    }
    final notifications = controller.notifications;
    if (notifications.isEmpty) {
      return EmptyState(
        icon: Icons.notifications_none_rounded,
        title: tr('Nothing new yet'),
        message: tr('Requests, approvals, and trip changes will appear here.'),
      );
    }
    return RefreshIndicator(
      onRefresh: controller.load,
      child: ListView.separated(
        itemCount: notifications.length,
        separatorBuilder: (context, index) => const Divider(),
        itemBuilder: (context, index) {
          final item = notifications[index];
          return ListTile(
            key: ValueKey('notification-${item.id}'),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xxs,
            ),
            leading: Icon(
              item.isRead
                  ? Icons.notifications_none_rounded
                  : Icons.notifications_active_rounded,
              color: item.isRead ? AppColors.muted : AppColors.terracotta,
            ),
            title: Text(
              item.message,
              style: item.isRead
                  ? null
                  : const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(formatTripDate(item.createdAt)),
            onTap: () => _open(context, ref, item),
          );
        },
      ),
    );
  }
}
