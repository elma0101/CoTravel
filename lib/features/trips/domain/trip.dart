import '../../../core/l10n/app_strings.dart';

enum TripStopType { waypoint, activity, overnight, breakStop }

extension TripStopTypeValue on TripStopType {
  String get storageValue => switch (this) {
    TripStopType.waypoint => 'waypoint',
    TripStopType.activity => 'activity',
    TripStopType.overnight => 'overnight',
    TripStopType.breakStop => 'break',
  };

  String get label => switch (this) {
    TripStopType.waypoint => tr('Waypoint'),
    TripStopType.activity => tr('Activity'),
    TripStopType.overnight => tr('Overnight'),
    TripStopType.breakStop => tr('Break'),
  };

  static TripStopType fromStorage(String? value) => switch (value) {
    'activity' => TripStopType.activity,
    'overnight' => TripStopType.overnight,
    'break' => TripStopType.breakStop,
    _ => TripStopType.waypoint,
  };
}

enum TripTravelMode { drive, sharedTaxi, train, bus, walk, other }

extension TripTravelModeValue on TripTravelMode {
  String get storageValue => switch (this) {
    TripTravelMode.drive => 'drive',
    TripTravelMode.sharedTaxi => 'shared_taxi',
    TripTravelMode.train => 'train',
    TripTravelMode.bus => 'bus',
    TripTravelMode.walk => 'walk',
    TripTravelMode.other => 'other',
  };

  String get label => switch (this) {
    TripTravelMode.drive => tr('Drive'),
    TripTravelMode.sharedTaxi => tr('Shared taxi'),
    TripTravelMode.train => tr('Train'),
    TripTravelMode.bus => tr('Bus'),
    TripTravelMode.walk => tr('Walk'),
    TripTravelMode.other => tr('Transfer'),
  };

  static TripTravelMode? fromStorage(String? value) => switch (value) {
    'drive' => TripTravelMode.drive,
    'shared_taxi' => TripTravelMode.sharedTaxi,
    'train' => TripTravelMode.train,
    'bus' => TripTravelMode.bus,
    'walk' => TripTravelMode.walk,
    'other' => TripTravelMode.other,
    _ => null,
  };
}

class GeoPoint {
  const GeoPoint(this.latitude, this.longitude)
    : assert(latitude >= -90 && latitude <= 90),
      assert(longitude >= -180 && longitude <= 180);

  final double latitude;
  final double longitude;
}

class TripStop {
  const TripStop({
    required this.city,
    required this.arrivalDate,
    this.notes,
    this.latitude,
    this.longitude,
    this.type = TripStopType.waypoint,
    this.travelMode,
    this.travelDurationMinutes,
    this.isOptional = false,
  }) : assert(
         (latitude == null && longitude == null) ||
             (latitude != null && longitude != null),
       ),
       assert(latitude == null || (latitude >= -90 && latitude <= 90)),
       assert(longitude == null || (longitude >= -180 && longitude <= 180)),
       assert(travelDurationMinutes == null || travelDurationMinutes > 0);

  final String city;
  final DateTime arrivalDate;
  final String? notes;
  final double? latitude;
  final double? longitude;
  final TripStopType type;
  final TripTravelMode? travelMode;
  final int? travelDurationMinutes;
  final bool isOptional;

  GeoPoint? get coordinate {
    final latitude = this.latitude;
    final longitude = this.longitude;
    return latitude == null || longitude == null
        ? null
        : GeoPoint(latitude, longitude);
  }

  TripStop copyWith({
    double? latitude,
    double? longitude,
    TripStopType? type,
    TripTravelMode? travelMode,
    int? travelDurationMinutes,
    bool? isOptional,
  }) {
    return TripStop(
      city: city,
      arrivalDate: arrivalDate,
      notes: notes,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      type: type ?? this.type,
      travelMode: travelMode ?? this.travelMode,
      travelDurationMinutes:
          travelDurationMinutes ?? this.travelDurationMinutes,
      isOptional: isOptional ?? this.isOptional,
    );
  }
}

enum TripStatus { published, closed, cancelled }

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
    this.status = TripStatus.published,
  });

  // Travelers can leave freely until this many days before departure.
  static const freeCancellationDays = 7;

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
  final TripStatus status;

  String get routeSummary {
    final places = [originCity, for (final stop in stops) stop.city];
    return places.join(' → ');
  }

  bool get isCancelled => status == TripStatus.cancelled;
  DateTime get freeCancellationUntil =>
      startDate.subtract(const Duration(days: freeCancellationDays));

  bool hasStarted(DateTime now) =>
      DateTime(now.year, now.month, now.day).isAfter(startDate);

  bool isLateToLeave(DateTime now) =>
      DateTime(now.year, now.month, now.day).isAfter(freeCancellationUntil);

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
    TripStatus? status,
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
      status: status ?? this.status,
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
