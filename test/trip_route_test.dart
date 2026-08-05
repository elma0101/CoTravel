import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/domain/trip_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripRoute', () {
    test('builds a mapped route from legacy city-only stops', () {
      final trip = _trip(
        originCity: 'Casablanca',
        stops: [
          TripStop(city: 'Marrakech', arrivalDate: DateTime(2027, 4, 2)),
          TripStop(city: 'Imlil', arrivalDate: DateTime(2027, 4, 3)),
        ],
      );

      final route = TripRoute.fromTrip(trip);

      expect(route.points, hasLength(3));
      expect(route.mappedPoints, hasLength(3));
      expect(route.canExplore, isTrue);
      expect(route.points.first.isOrigin, isTrue);
      expect(route.points.last.coordinate?.latitude, closeTo(31.1370, 0.0001));
    });

    test('keeps explicit stop coordinates and interaction metadata', () {
      final trip = _trip(
        originCity: 'Casablanca',
        stops: [
          TripStop(
            city: 'Custom mountain camp',
            arrivalDate: DateTime(2027, 4, 2),
            latitude: 31.101,
            longitude: -7.901,
            type: TripStopType.overnight,
            travelMode: TripTravelMode.walk,
            travelDurationMinutes: 95,
            isOptional: true,
          ),
        ],
      );

      final point = TripRoute.fromTrip(trip).points.last;

      expect(point.coordinate?.longitude, -7.901);
      expect(point.type, TripStopType.overnight);
      expect(point.travelMode, TripTravelMode.walk);
      expect(point.travelDurationMinutes, 95);
      expect(point.isOptional, isTrue);
    });

    test('retains unmapped stops without drawing invalid markers', () {
      final trip = _trip(
        originCity: 'Unknown origin',
        stops: [
          TripStop(
            city: 'Unknown destination',
            arrivalDate: DateTime(2027, 4, 2),
          ),
        ],
      );

      final route = TripRoute.fromTrip(trip);

      expect(route.points, hasLength(2));
      expect(route.mappedPoints, isEmpty);
      expect(route.canExplore, isFalse);
    });
  });
}

Trip _trip({required String originCity, required List<TripStop> stops}) {
  return Trip(
    id: 'trip',
    hostId: 'host',
    hostName: 'Host',
    hostHomeCity: 'Casablanca',
    hostVerified: true,
    title: 'Route test',
    originCity: originCity,
    startDate: DateTime(2027, 4),
    endDate: DateTime(2027, 4, 5),
    stops: stops,
    capacity: 4,
    confirmedTravelerCount: 0,
    lodgingTotal: 1000,
    transportTotal: 500,
    currency: 'MAD',
    travelStyle: 'Nature',
    summary: 'A route used to verify the interactive explorer domain model.',
  );
}
