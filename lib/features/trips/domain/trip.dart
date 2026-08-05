class TripStop {
  const TripStop({required this.city, required this.arrivalDate, this.notes});

  final String city;
  final DateTime arrivalDate;
  final String? notes;
}

class TripDraft {
  const TripDraft({
    required this.title,
    required this.originCity,
    required this.startDate,
    required this.endDate,
    required this.stops,
    required this.capacity,
    required this.lodgingTotal,
    required this.transportTotal,
    required this.currency,
    required this.travelStyle,
    required this.summary,
  });

  final String title;
  final String originCity;
  final DateTime startDate;
  final DateTime endDate;
  final List<TripStop> stops;
  final int capacity;
  final double lodgingTotal;
  final double transportTotal;
  final String currency;
  final String travelStyle;
  final String summary;
}

class Trip {
  const Trip({
    required this.id,
    required this.hostId,
    required this.hostName,
    required this.hostHomeCity,
    required this.hostVerified,
    required this.title,
    required this.originCity,
    required this.startDate,
    required this.endDate,
    required this.stops,
    required this.capacity,
    required this.confirmedTravelerCount,
    required this.lodgingTotal,
    required this.transportTotal,
    required this.currency,
    required this.travelStyle,
    required this.summary,
  });

  final String id;
  final String hostId;
  final String hostName;
  final String? hostHomeCity;
  final bool hostVerified;
  final String title;
  final String originCity;
  final DateTime startDate;
  final DateTime endDate;
  final List<TripStop> stops;
  final int capacity;
  final int confirmedTravelerCount;
  final double lodgingTotal;
  final double transportTotal;
  final String currency;
  final String travelStyle;
  final String summary;

  String get destinationCity => stops.last.city;
  int get participantCount => 1 + confirmedTravelerCount;
  int get openSeats => capacity - participantCount;
  double get totalCost => lodgingTotal + transportTotal;
  double get estimatedFullGroupShare => totalCost / capacity;
  double get currentGroupShare => totalCost / participantCount;
  int get durationDays => endDate.difference(startDate).inDays + 1;

  Trip copyWith({
    int? confirmedTravelerCount,
    double? lodgingTotal,
    double? transportTotal,
  }) {
    return Trip(
      id: id,
      hostId: hostId,
      hostName: hostName,
      hostHomeCity: hostHomeCity,
      hostVerified: hostVerified,
      title: title,
      originCity: originCity,
      startDate: startDate,
      endDate: endDate,
      stops: stops,
      capacity: capacity,
      confirmedTravelerCount:
          confirmedTravelerCount ?? this.confirmedTravelerCount,
      lodgingTotal: lodgingTotal ?? this.lodgingTotal,
      transportTotal: transportTotal ?? this.transportTotal,
      currency: currency,
      travelStyle: travelStyle,
      summary: summary,
    );
  }
}

class TripFilter {
  const TripFilter({
    this.originQuery = '',
    this.destinationQuery = '',
    this.startDate,
    this.endDate,
    this.travelStyle,
    this.verifiedHostsOnly = false,
  });

  final String originQuery;
  final String destinationQuery;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? travelStyle;
  final bool verifiedHostsOnly;

  bool get isActive =>
      originQuery.trim().isNotEmpty ||
      destinationQuery.trim().isNotEmpty ||
      startDate != null ||
      endDate != null ||
      travelStyle != null ||
      verifiedHostsOnly;

  bool matches(Trip trip) {
    final normalizedOrigin = originQuery.trim().toLowerCase();
    final normalizedDestination = destinationQuery.trim().toLowerCase();
    final routeCities = trip.stops.map((stop) => stop.city.toLowerCase());

    if (normalizedOrigin.isNotEmpty &&
        !trip.originCity.toLowerCase().contains(normalizedOrigin)) {
      return false;
    }
    if (normalizedDestination.isNotEmpty &&
        !routeCities.any((city) => city.contains(normalizedDestination))) {
      return false;
    }
    if (startDate != null && trip.startDate.isBefore(_dateOnly(startDate!))) {
      return false;
    }
    if (endDate != null && trip.startDate.isAfter(_dateOnly(endDate!))) {
      return false;
    }
    if (travelStyle != null && trip.travelStyle != travelStyle) {
      return false;
    }
    if (verifiedHostsOnly && !trip.hostVerified) {
      return false;
    }
    return true;
  }

  TripFilter copyWith({
    String? originQuery,
    String? destinationQuery,
    DateTime? startDate,
    DateTime? endDate,
    String? travelStyle,
    bool clearTravelStyle = false,
    bool? verifiedHostsOnly,
  }) {
    return TripFilter(
      originQuery: originQuery ?? this.originQuery,
      destinationQuery: destinationQuery ?? this.destinationQuery,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      travelStyle: clearTravelStyle ? null : (travelStyle ?? this.travelStyle),
      verifiedHostsOnly: verifiedHostsOnly ?? this.verifiedHostsOnly,
    );
  }

  static DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }
}
