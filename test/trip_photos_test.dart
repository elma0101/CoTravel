import 'dart:convert';

import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/trip_card.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/trip_photos_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// A 1×1 transparent PNG.
final _pixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

NewTripPhoto _newPhoto() => NewTripPhoto(bytes: _pixel, extension: 'png');

Future<TripCatalogController> _loadedCatalog() async {
  final catalog = TripCatalogController(
    repository: PreviewTripRepository(),
    userId: 'preview-user',
    hostProfile: UserProfile.preview(),
  );
  await catalog.load();
  return catalog;
}

void main() {
  test('new photos follow the ones the host kept', () async {
    final catalog = await _loadedCatalog();
    final trip = catalog.discoverableTrips.first;

    final first = await catalog.saveTripPhotos(
      trip,
      kept: const [],
      added: [_newPhoto(), _newPhoto()],
    );
    final second = await catalog.saveTripPhotos(
      first,
      kept: [first.photos.last],
      added: [_newPhoto()],
    );

    expect(first.photos, hasLength(2));
    expect(second.photos, hasLength(2));
    expect(second.photos.first.path, first.photos.last.path);
    expect(catalog.tripById(trip.id)!.photos, hasLength(2));
  });

  test('a trip takes at most five photos', () async {
    final catalog = await _loadedCatalog();
    final trip = catalog.discoverableTrips.first;

    await expectLater(
      catalog.saveTripPhotos(
        trip,
        kept: const [],
        added: List.generate(Trip.maxPhotos + 1, (_) => _newPhoto()),
      ),
      throwsStateError,
    );
  });

  test('editing a trip keeps its photos', () async {
    final catalog = await _loadedCatalog();
    final hosted = await catalog.createTrip(
      TripDraft(
        title: 'Coast weekend',
        originCity: 'Rabat',
        startDate: DateTime(2030, 5, 1),
        endDate: DateTime(2030, 5, 3),
        stops: [TripStop(city: 'Essaouira', arrivalDate: DateTime(2030, 5, 2))],
        capacity: 4,
        lodgingTotal: 400,
        transportTotal: 200,
        currency: 'MAD',
        travelStyle: 'Nature',
        summary: 'A calm weekend by the ocean with long walks.',
      ),
    );
    final withPhotos = await catalog.saveTripPhotos(
      hosted,
      kept: const [],
      added: [_newPhoto()],
    );

    final edited = await catalog.updateTrip(
      hosted.id,
      TripDraft(
        title: 'Coast long weekend',
        originCity: withPhotos.originCity,
        startDate: withPhotos.startDate,
        endDate: withPhotos.endDate,
        stops: withPhotos.stops,
        capacity: withPhotos.capacity,
        lodgingTotal: withPhotos.lodgingTotal,
        transportTotal: withPhotos.transportTotal,
        currency: withPhotos.currency,
        travelStyle: withPhotos.travelStyle,
        summary: withPhotos.summary,
      ),
    );

    expect(edited.photos.single.path, withPhotos.photos.single.path);
  });

  testWidgets('a card shows the host photo instead of a built-in one', (
    tester,
  ) async {
    final catalog = await tester.runAsync(_loadedCatalog);
    final trip = catalog!.discoverableTrips.first.copyWith(
      photos: [TripPhoto(path: 'trip/one.png', url: '', bytes: _pixel)],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TripCard(trip: trip, onTap: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The card merges its parts into one label.
    expect(
      find.bySemanticsLabel(RegExp('Photo of ${trip.destinationCity}')),
      findsOneWidget,
    );
    expect(find.byTooltip('Photo details'), findsNothing);
  });

  testWidgets('the editor stops offering more photos at the limit', (
    tester,
  ) async {
    var removed = -1;
    Widget editor(int count) => MaterialApp(
      home: Scaffold(
        body: TripPhotosEditor(
          kept: const [],
          added: List.generate(count, (_) => _newPhoto()),
          onAdd: () {},
          onRemoveKept: (_) {},
          onRemoveAdded: (index) => removed = index,
        ),
      ),
    );

    await tester.pumpWidget(editor(1));
    expect(find.byKey(const ValueKey('trip-add-photos')), findsOneWidget);
    expect(find.text('Cover'), findsOneWidget);
    await tester.tap(find.byTooltip('Remove photo'));
    expect(removed, 0);

    await tester.pumpWidget(editor(Trip.maxPhotos));
    expect(find.byKey(const ValueKey('trip-add-photos')), findsNothing);
  });
}
