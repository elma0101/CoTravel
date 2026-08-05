import 'package:cotravel_app/core/analytics/product_analytics.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/safety/application/safety_controller.dart';
import 'package:cotravel_app/features/safety/data/safety_repository.dart';
import 'package:cotravel_app/features/safety/domain/safety_models.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late TripCatalogController catalog;
  late SafetyController safety;
  late PreviewProductAnalytics analytics;

  setUp(() async {
    final trips = PreviewTripRepository(today: DateTime(2026, 8, 5));
    catalog = TripCatalogController(
      repository: trips,
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
    );
    analytics = PreviewProductAnalytics();
    safety = SafetyController(
      repository: PreviewSafetyRepository(),
      tripCatalog: catalog,
      analytics: analytics,
    );
    await catalog.load();
    await safety.load();
  });

  tearDown(() {
    safety.dispose();
    catalog.dispose();
  });

  test(
    'report preserves trip context and enters manual review queue',
    () async {
      const target = SafetyTarget(
        userId: 'host-salma',
        userName: 'Salma R.',
        tripId: 'northern-colors',
        tripTitle: 'Northern colors',
      );

      final report = await safety.submitReport(
        target: target,
        reason: SafetyReportReason.unsafePlan,
        details: 'The departure instructions describe an unsafe meeting point.',
      );

      expect(report.status, SafetyReportStatus.submitted);
      expect(report.tripId, target.tripId);
      expect(safety.reports.single.subjectName, target.userName);
      expect(analytics.events.single.event, ProductEvent.safetyReportSubmitted);
      expect(analytics.events.single.properties['reason'], 'unsafe_plan');
    },
  );

  test(
    'blocking immediately filters discovery and unblocking restores it',
    () async {
      const target = SafetyTarget(
        userId: 'host-salma',
        userName: 'Salma R.',
        tripId: 'northern-colors',
        tripTitle: 'Northern colors',
      );
      expect(catalog.discoverableTrips, hasLength(5));

      await safety.block(target);

      expect(safety.isBlocked(target.userId), isTrue);
      expect(catalog.discoverableTrips, hasLength(4));
      expect(catalog.tripById(target.tripId!), isNull);
      expect(analytics.events.single.event, ProductEvent.userBlocked);

      await safety.unblock(target.userId);

      expect(safety.isBlocked(target.userId), isFalse);
      expect(catalog.discoverableTrips, hasLength(5));
      expect(catalog.tripById(target.tripId!), isNotNull);
    },
  );
}
