import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

class _RefusingRepository extends PreviewTripRepository {
  @override
  Future<void> saveTrip({
    required String userId,
    required String tripId,
  }) async {
    throw StateError('offline');
  }
}

TripCatalogController _controller(TripRepository repository) {
  return TripCatalogController(
    repository: repository,
    userId: 'preview-user',
    hostProfile: UserProfile.preview(),
  );
}

void main() {
  test('saving and removing keeps the list and the server in step', () async {
    final repository = PreviewTripRepository();
    final catalog = _controller(repository);
    await catalog.load();
    final trip = catalog.discoverableTrips.first;

    await catalog.toggleSaved(trip);
    expect(catalog.isSaved(trip.id), isTrue);
    expect(await repository.fetchSavedTrips('preview-user'), hasLength(1));

    await catalog.toggleSaved(trip);
    expect(catalog.savedTrips, isEmpty);
    expect(await repository.fetchSavedTrips('preview-user'), isEmpty);
  });

  test('a refused save puts the list back', () async {
    final catalog = _controller(_RefusingRepository());
    await catalog.load();
    final trip = catalog.discoverableTrips.first;

    await expectLater(catalog.toggleSaved(trip), throwsStateError);

    expect(catalog.isSaved(trip.id), isFalse);
  });

  test('a blocked host disappears from saved trips', () async {
    final catalog = _controller(PreviewTripRepository());
    await catalog.load();
    final trip = catalog.discoverableTrips.first;
    await catalog.toggleSaved(trip);

    catalog.setBlockedHosts({trip.hostId});

    expect(catalog.savedTrips, isEmpty);
  });
}
