import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/domain/trip_route.dart';
import 'package:flutter_test/flutter_test.dart';

TripDraft _draft({required String origin, GeoPoint? point}) {
  final start = DateTime(2026, 12, 10);
  return TripDraft(
    title: 'Station start',
    originCity: origin,
    originCoordinate: point,
    startDate: start,
    endDate: start.add(const Duration(days: 2)),
    stops: [TripStop(city: 'Rabat', arrivalDate: start)],
    capacity: 4,
    lodgingTotal: 300,
    transportTotal: 100,
    currency: 'MAD',
    travelStyle: 'Culture',
    summary: 'A short trip that starts at the main station.',
  );
}

void main() {
  const station = GeoPoint(33.5902, -7.5900);

  test('the route starts at the picked departure point', () async {
    final repository = PreviewTripRepository(today: DateTime(2026, 11, 2));
    final trip = await repository.createTrip(
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
      draft: _draft(origin: 'Casa Voyageurs, Casablanca', point: station),
    );

    final origin = TripRoute.fromTrip(trip).points.first.coordinate;
    expect(origin?.latitude, station.latitude);
    expect(origin?.longitude, station.longitude);
  });

  test('a departure without a point still starts at its town', () async {
    final repository = PreviewTripRepository(today: DateTime(2026, 11, 2));
    final trip = await repository.createTrip(
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
      draft: _draft(origin: 'Casa Voyageurs, Casablanca'),
    );

    final origin = TripRoute.fromTrip(trip).points.first.coordinate;
    expect(
      origin?.latitude,
      MoroccoRouteCoordinates.lookup('Casablanca')?.latitude,
    );
  });

  test('editing keeps the point until the departure is renamed', () async {
    final repository = PreviewTripRepository(today: DateTime(2026, 11, 2));
    final trip = await repository.createTrip(
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
      draft: _draft(origin: 'Casa Voyageurs, Casablanca', point: station),
    );

    final unchanged = await repository.updateTrip(
      tripId: trip.id,
      draft: _draft(origin: 'Casa Voyageurs, Casablanca'),
    );
    expect(unchanged.originCoordinate?.latitude, station.latitude);

    final renamed = await repository.updateTrip(
      tripId: trip.id,
      draft: _draft(origin: 'Rabat'),
    );
    expect(renamed.originCoordinate, isNull);
  });
}
