import 'package:cotravel_app/features/logistics/application/logistics_controller.dart';
import 'package:cotravel_app/features/logistics/data/logistics_repository.dart';
import 'package:cotravel_app/features/logistics/domain/trip_logistics.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('cost estimate responds to every group size up to capacity', () async {
    final trips = PreviewTripRepository(today: DateTime(2026, 8, 5));
    final trip = (await trips.fetchTrip('dades-slow-road'))!;

    final solo = SharedCostEstimate.forTrip(trip, 1);
    final current = SharedCostEstimate.forTrip(trip, trip.participantCount);
    final full = SharedCostEstimate.forTrip(trip, trip.capacity);

    expect(solo.totalPerPerson, 7400);
    expect(current.totalPerPerson, closeTo(2466.67, 0.01));
    expect(full.lodgingPerPerson, 1000);
    expect(full.transportPerPerson, 480);
    expect(
      () => SharedCostEstimate.forTrip(trip, trip.capacity + 1),
      throwsRangeError,
    );
  });

  test(
    'host logistics update refreshes booking details and trip costs',
    () async {
      final trips = PreviewTripRepository(today: DateTime(2026, 8, 5));
      final catalog = TripCatalogController(
        repository: trips,
        userId: 'preview-user',
        hostProfile: const UserProfile.preview(),
      );
      final repository = PreviewLogisticsRepository(tripRepository: trips);
      final controller = LogisticsController(
        repository: repository,
        tripCatalog: catalog,
      );
      addTearDown(() {
        controller.dispose();
        catalog.dispose();
      });

      await catalog.load();
      final trip = catalog.tripById('preview-rif-loop')!;
      expect((await controller.load(trip.id)).hasBookingLinks, isFalse);

      await controller.save(
        trip: trip,
        draft: LogisticsDraft(
          lodgingTotal: 4200,
          transportTotal: 1800,
          accommodationName: 'Rif guesthouse shortlist',
          accommodationUrl: Uri.parse('https://www.airbnb.com/'),
          transportName: 'Intercity transfer',
          transportUrl: Uri.parse('https://indrive.com/'),
          notes: 'Compare both options before the group confirms a booking.',
        ),
      );

      final updatedTrip = catalog.tripById(trip.id)!;
      final updatedPlan = controller.planForTrip(trip.id)!;
      expect(updatedTrip.lodgingTotal, 4200);
      expect(updatedTrip.transportTotal, 1800);
      expect(updatedPlan.accommodationName, 'Rif guesthouse shortlist');
      expect(updatedPlan.hasBookingLinks, isTrue);
    },
  );
}
