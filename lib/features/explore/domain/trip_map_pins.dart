import '../../trips/domain/trip.dart';
import '../../trips/domain/trip_route.dart';

/// All open trips ending at one place.
class TripMapPin {
  const TripMapPin({
    required this.place,
    required this.coordinate,
    required this.trips,
  });

  final String place;
  final GeoPoint coordinate;
  final List<Trip> trips;
}

class TripMapPins {
  const TripMapPins({required this.pins, required this.unmappedCount});

  /// Pins go at each trip's destination. A trip whose destination has no
  /// coordinates is counted, so the map never silently hides it.
  factory TripMapPins.fromTrips(List<Trip> trips) {
    final grouped = <String, List<Trip>>{};
    final coordinates = <String, GeoPoint>{};
    var unmapped = 0;
    for (final trip in trips) {
      final coordinate = _destinationCoordinate(trip);
      if (coordinate == null) {
        unmapped++;
        continue;
      }
      final key = '${coordinate.latitude},${coordinate.longitude}';
      coordinates[key] = coordinate;
      (grouped[key] ??= []).add(trip);
    }
    final pins = [
      for (final entry in grouped.entries)
        TripMapPin(
          place: entry.value.first.destinationCity,
          coordinate: coordinates[entry.key]!,
          trips: List.unmodifiable(entry.value),
        ),
    ]..sort((left, right) => left.place.compareTo(right.place));
    return TripMapPins(pins: pins, unmappedCount: unmapped);
  }

  final List<TripMapPin> pins;
  final int unmappedCount;

  static GeoPoint? _destinationCoordinate(Trip trip) {
    return trip.stops.last.coordinate ??
        MoroccoRouteCoordinates.lookup(trip.destinationCity);
  }
}
