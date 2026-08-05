import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/trip_cover_images.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each preview itinerary has a distinct local cover photo', () async {
    final repository = PreviewTripRepository(today: DateTime(2026, 8, 5));
    final trips = await repository.discoverTrips();
    final covers = trips.map(TripCoverImages.forTrip).toList();

    expect(covers, everyElement(isNotNull));
    expect(covers.map((cover) => cover!.assetPath).toSet(), hasLength(5));
  });
}
