import '../../trips/domain/trip.dart';

class TripLogistics {
  const TripLogistics({
    required this.tripId,
    this.accommodationName,
    this.accommodationUrl,
    this.transportName,
    this.transportUrl,
    this.notes,
    this.updatedAt,
  });

  final String tripId;
  final String? accommodationName;
  final Uri? accommodationUrl;
  final String? transportName;
  final Uri? transportUrl;
  final String? notes;
  final DateTime? updatedAt;

  bool get hasBookingLinks => accommodationUrl != null || transportUrl != null;
}

class LogisticsDraft {
  const LogisticsDraft({
    required this.lodgingTotal,
    required this.transportTotal,
    this.accommodationName,
    this.accommodationUrl,
    this.transportName,
    this.transportUrl,
    this.notes,
  });

  final double lodgingTotal;
  final double transportTotal;
  final String? accommodationName;
  final Uri? accommodationUrl;
  final String? transportName;
  final Uri? transportUrl;
  final String? notes;
}

class SharedCostEstimate {
  const SharedCostEstimate._({
    required this.travelerCount,
    required this.lodgingPerPerson,
    required this.transportPerPerson,
  });

  factory SharedCostEstimate.forTrip(Trip trip, int travelerCount) {
    if (travelerCount < 1 || travelerCount > trip.capacity) {
      throw RangeError.range(travelerCount, 1, trip.capacity, 'travelerCount');
    }
    return SharedCostEstimate._(
      travelerCount: travelerCount,
      lodgingPerPerson: trip.lodgingTotal / travelerCount,
      transportPerPerson: trip.transportTotal / travelerCount,
    );
  }

  final int travelerCount;
  final double lodgingPerPerson;
  final double transportPerPerson;

  double get totalPerPerson => lodgingPerPerson + transportPerPerson;
}
