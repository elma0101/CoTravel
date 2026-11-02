import '../../../core/l10n/app_strings.dart';

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
    final actor = actorName ?? tr('Someone');
    return switch (kind) {
      NotificationKind.joinRequestReceived => tr(
        '{actor} asked to join {tripTitle}.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.requestApproved => tr(
        '{actor} approved your request for {tripTitle}. Confirm to lock your place.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.requestDeclined => tr(
        'Your request for {tripTitle} was not accepted.',
        {'tripTitle': tripTitle},
      ),
      NotificationKind.travelerConfirmed => tr(
        '{actor} confirmed their place on {tripTitle}.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.travelerDeclined => tr(
        '{actor} declined the invitation to {tripTitle}.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.travelerWithdrew => tr(
        '{actor} withdrew their request for {tripTitle}.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.travelerLeft => tr('{actor} left {tripTitle}.', {
        'actor': actor,
        'tripTitle': tripTitle,
      }),
      NotificationKind.travelerLeftLate => tr(
        '{actor} left {tripTitle} within 7 days of departure.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.tripUpdated => tr(
        '{actor} updated {tripTitle}. Check the latest plan.',
        {'actor': actor, 'tripTitle': tripTitle},
      ),
      NotificationKind.tripCancelled => tr('{actor} cancelled {tripTitle}.', {
        'actor': actor,
        'tripTitle': tripTitle,
      }),
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
