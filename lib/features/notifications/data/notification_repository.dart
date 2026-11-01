import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_notification.dart';

abstract interface class NotificationRepository {
  Future<List<AppNotification>> fetchNotifications();

  Future<void> markRead(String notificationId);

  Future<void> markAllRead();

  Stream<void> watchNotifications();
}

class SupabaseNotificationRepository implements NotificationRepository {
  SupabaseNotificationRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    final rows = await _client
        .from('notifications')
        .select()
        .order('created_at', ascending: false)
        .limit(50);
    return rows
        .where((row) => NotificationKind.fromStorage(row['kind']) != null)
        .map(_fromMap)
        .toList();
  }

  @override
  Future<void> markRead(String notificationId) async {
    await _client.rpc(
      'mark_notifications_read',
      params: {'p_notification_id': notificationId},
    );
  }

  @override
  Future<void> markAllRead() async {
    await _client.rpc('mark_notifications_read');
  }

  @override
  Stream<void> watchNotifications() {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      return const Stream.empty();
    }

    late RealtimeChannel channel;
    late StreamController<void> controller;

    controller = StreamController<void>(
      onListen: () {
        channel = _client
            .channel('notifications-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'notifications',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'user_id',
                value: userId,
              ),
              callback: (_) => controller.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  AppNotification _fromMap(Map<String, dynamic> row) {
    return AppNotification(
      id: row['id'] as String,
      kind: NotificationKind.fromStorage(row['kind'] as String)!,
      tripId: row['trip_id'] as String?,
      tripTitle: row['trip_title'] as String,
      actorName: row['actor_name'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      isRead: row['read_at'] != null,
    );
  }
}

class PreviewNotificationRepository implements NotificationRepository {
  PreviewNotificationRepository({DateTime? now})
    : _notifications = _seed(now ?? DateTime.now());

  final List<AppNotification> _notifications;

  @override
  Future<List<AppNotification>> fetchNotifications() async {
    return List.of(_notifications);
  }

  @override
  Future<void> markRead(String notificationId) async {
    final index = _notifications.indexWhere(
      (notification) => notification.id == notificationId,
    );
    if (index != -1) {
      _notifications[index] = _notifications[index].markedRead();
    }
  }

  @override
  Future<void> markAllRead() async {
    for (var index = 0; index < _notifications.length; index++) {
      _notifications[index] = _notifications[index].markedRead();
    }
  }

  @override
  Stream<void> watchNotifications() => const Stream.empty();

  static List<AppNotification> _seed(DateTime now) {
    return [
      AppNotification(
        id: 'preview-notification-request',
        kind: NotificationKind.joinRequestReceived,
        tripId: 'preview-rif-loop',
        tripTitle: 'Rif towns and trails',
        actorName: 'Nadia K.',
        createdAt: now.subtract(const Duration(hours: 2)),
        isRead: false,
      ),
      AppNotification(
        id: 'preview-notification-approval',
        kind: NotificationKind.requestApproved,
        tripId: 'atlas-weekend',
        tripTitle: 'Atlas villages weekend',
        actorName: 'Amina B.',
        createdAt: now.subtract(const Duration(days: 1)),
        isRead: false,
      ),
    ];
  }
}
