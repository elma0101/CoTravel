import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripFilter', () {
    final trip = Trip(
      id: 'trip-1',
      hostId: 'host-1',
      hostName: 'Amina',
      hostHomeCity: 'Casablanca',
      hostVerified: true,
      title: 'Mountain weekend',
      originCity: 'Casablanca',
      startDate: DateTime(2026, 9, 10),
      endDate: DateTime(2026, 9, 13),
      stops: [
        TripStop(city: 'Marrakech', arrivalDate: DateTime(2026, 9, 10)),
        TripStop(city: 'Imlil', arrivalDate: DateTime(2026, 9, 11)),
      ],
      capacity: 5,
      confirmedTravelerCount: 1,
      lodgingTotal: 3000,
      transportTotal: 1000,
      currency: 'MAD',
      travelStyle: 'Nature',
      summary: 'A thoughtful mountain weekend with a small group.',
    );

    test('matches intermediate stops and host trust filters', () {
      expect(
        const TripFilter(
          destinationQuery: 'marr',
          travelStyle: 'Nature',
          verifiedHostsOnly: true,
        ).matches(trip),
        isTrue,
      );
      expect(
        const TripFilter(destinationQuery: 'Essaouira').matches(trip),
        isFalse,
      );
    });

    test('calculates seats and projected group share', () {
      expect(trip.participantCount, 2);
      expect(trip.openSeats, 3);
      expect(trip.estimatedFullGroupShare, 800);
      expect(trip.currentGroupShare, 2000);
    });
  });

  test('preview catalog publishes and immediately discovers a trip', () async {
    final repository = PreviewTripRepository(today: DateTime(2026, 8, 5));
    final controller = TripCatalogController(
      repository: repository,
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
    );
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.discoverableTrips, hasLength(5));
    expect(controller.hostedTrips.single.id, 'preview-rif-loop');

    final start = DateTime(2026, 10, 4);
    final created = await controller.createTrip(
      TripDraft(
        title: 'Desert night skies',
        originCity: 'Ouarzazate',
        startDate: start,
        endDate: start.add(const Duration(days: 2)),
        stops: [
          TripStop(city: 'Mhamid', arrivalDate: start),
          TripStop(
            city: 'Erg Chigaga',
            arrivalDate: start.add(const Duration(days: 1)),
          ),
        ],
        capacity: 4,
        lodgingTotal: 2400,
        transportTotal: 1600,
        currency: 'MAD',
        travelStyle: 'Nature',
        summary:
            'Two quiet nights focused on desert landscapes and clear skies.',
      ),
    );

    expect(created.hostId, 'preview-user');
    expect(controller.hostedTrips.map((trip) => trip.id), contains(created.id));
    expect(controller.discoverableTrips, hasLength(6));

    controller.applyFilter(const TripFilter(destinationQuery: 'Chigaga'));
    expect(controller.discoverableTrips.single.id, created.id);
  });
}
