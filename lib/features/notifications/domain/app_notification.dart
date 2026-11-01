enum NotificationKind {
  joinRequestReceived('join_request_received'),
  requestApproved('request_approved'),
  requestDeclined('request_declined'),
  travelerConfirmed('traveler_confirmed'),
  travelerDeclined('traveler_declined'),
  travelerWithdrew('traveler_withdrew'),
  travelerLeft('traveler_left'),
  travelerLeftLate('traveler_left_late'),
  tripUpdated('trip_updated'),
  tripCancelled('trip_cancelled');

  const NotificationKind(this.storageValue);

  final String storageValue;

  static NotificationKind? fromStorage(String? value) {
    for (final kind in values) {
      if (kind.storageValue == value) {
        return kind;
      }
    }
    return null;
  }
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.tripId,
    required this.tripTitle,
    required this.actorName,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final NotificationKind kind;
  final String? tripId;
  final String tripTitle;
  final String? actorName;
  final DateTime createdAt;
  final bool isRead;

  String get message {
    final actor = actorName ?? 'Someone';
    return switch (kind) {
      NotificationKind.joinRequestReceived =>
        '$actor asked to join $tripTitle.',
      NotificationKind.requestApproved =>
        '$actor approved your request for $tripTitle. Confirm to lock your place.',
      NotificationKind.requestDeclined =>
        'Your request for $tripTitle was not accepted.',
      NotificationKind.travelerConfirmed =>
        '$actor confirmed their place on $tripTitle.',
      NotificationKind.travelerDeclined =>
        '$actor declined the invitation to $tripTitle.',
      NotificationKind.travelerWithdrew =>
        '$actor withdrew their request for $tripTitle.',
      NotificationKind.travelerLeft => '$actor left $tripTitle.',
      NotificationKind.travelerLeftLate =>
        '$actor left $tripTitle within 7 days of departure.',
      NotificationKind.tripUpdated =>
        '$actor updated $tripTitle. Check the latest plan.',
      NotificationKind.tripCancelled => '$actor cancelled $tripTitle.',
    };
  }

  AppNotification markedRead() {
    return AppNotification(
      id: id,
      kind: kind,
      tripId: tripId,
      tripTitle: tripTitle,
      actorName: actorName,
      createdAt: createdAt,
      isRead: true,
    );
  }
}
