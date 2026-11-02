import '../../../core/l10n/app_strings.dart';

enum JoinRequestStatus {
  pendingHost,
  pendingTraveler,
  confirmed,
  declined,
  withdrawn,
  left,
}

extension JoinRequestStatusPresentation on JoinRequestStatus {
  String get label {
    return switch (this) {
      JoinRequestStatus.pendingHost => tr('Awaiting host'),
      JoinRequestStatus.pendingTraveler => tr('Your confirmation needed'),
      JoinRequestStatus.confirmed => tr('Spot confirmed'),
      JoinRequestStatus.declined => tr('Not accepted'),
      JoinRequestStatus.withdrawn => tr('Withdrawn'),
      JoinRequestStatus.left => tr('Left the trip'),
    };
  }

  bool get isActive =>
      this == JoinRequestStatus.pendingHost ||
      this == JoinRequestStatus.pendingTraveler ||
      this == JoinRequestStatus.confirmed;
}

class TripJoinRequest {
  const TripJoinRequest({
    required this.id,
    required this.tripId,
    required this.hostId,
    required this.tripTitle,
    required this.originCity,
    required this.destinationCity,
    required this.startDate,
    required this.travelerId,
    required this.travelerName,
    required this.travelerBio,
    required this.travelerHomeCity,
    required this.travelerVerified,
    required this.message,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String tripId;
  final String hostId;
  final String tripTitle;
  final String originCity;
  final String destinationCity;
  final DateTime startDate;
  final String travelerId;
  final String travelerName;
  final String? travelerBio;
  final String? travelerHomeCity;
  final bool travelerVerified;
  final String message;
  final JoinRequestStatus status;
  final DateTime createdAt;

  String get routeLabel => '$originCity to $destinationCity';

  TripJoinRequest copyWith({JoinRequestStatus? status}) {
    return TripJoinRequest(
      id: id,
      tripId: tripId,
      hostId: hostId,
      tripTitle: tripTitle,
      originCity: originCity,
      destinationCity: destinationCity,
      startDate: startDate,
      travelerId: travelerId,
      travelerName: travelerName,
      travelerBio: travelerBio,
      travelerHomeCity: travelerHomeCity,
      travelerVerified: travelerVerified,
      message: message,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }
}
