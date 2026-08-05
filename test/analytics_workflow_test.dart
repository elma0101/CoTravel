import 'package:cotravel_app/core/analytics/product_analytics.dart';
import 'package:cotravel_app/features/join_requests/application/join_request_controller.dart';
import 'package:cotravel_app/features/join_requests/data/join_request_repository.dart';
import 'package:cotravel_app/features/join_requests/domain/trip_join_request.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('critical product flows emit privacy-minimized KPI events', () async {
    final now = DateTime(2026, 8, 5);
    final analytics = PreviewProductAnalytics();
    final trips = PreviewTripRepository(today: now);
    final catalog = TripCatalogController(
      repository: trips,
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
      analytics: analytics,
    );
    final requests = JoinRequestController(
      repository: PreviewJoinRequestRepository(tripRepository: trips, now: now),
      userId: 'preview-user',
      profile: const UserProfile.preview(),
      tripCatalog: catalog,
      analytics: analytics,
    );
    addTearDown(() {
      requests.dispose();
      catalog.dispose();
    });

    await catalog.load();
    await requests.load();
    final start = now.add(const Duration(days: 60));
    final published = await catalog.createTrip(
      TripDraft(
        title: 'Quiet desert camp',
        originCity: 'Ouarzazate',
        startDate: start,
        endDate: start.add(const Duration(days: 2)),
        stops: [TripStop(city: 'Mhamid', arrivalDate: start)],
        capacity: 4,
        lodgingTotal: 2400,
        transportTotal: 1200,
        currency: 'MAD',
        travelStyle: 'Nature',
        summary: 'A calm desert weekend with a small and considerate group.',
      ),
    );
    expect(analytics.events.last.event, ProductEvent.tripPublished);
    expect(analytics.events.last.tripId, published.id);
    expect(
      analytics.events.last.properties.keys,
      unorderedEquals(['capacity', 'travel_style']),
    );

    await requests.submitRequest(
      trip: catalog.tripById('northern-colors')!,
      message:
          'I enjoy thoughtful cultural weekends and can help coordinate travel.',
    );
    expect(analytics.events.last.event, ProductEvent.joinRequestSubmitted);

    final approval = requests.travelerRequests.firstWhere(
      (request) => request.status == JoinRequestStatus.pendingTraveler,
    );
    await requests.confirmAsTraveler(approval, confirm: true);
    expect(
      analytics.events
          .skip(analytics.events.length - 2)
          .map((event) => event.event),
      [ProductEvent.tripPlaceConfirmed, ProductEvent.groupCreated],
    );
    for (final event in analytics.events) {
      expect(event.properties, isNot(contains('email')));
      expect(event.properties, isNot(contains('message')));
      expect(event.properties, isNot(contains('details')));
    }
  });
}
