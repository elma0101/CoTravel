import 'package:cotravel_app/features/explore/domain/trip_map_pins.dart';
import 'package:cotravel_app/features/explore/presentation/trip_map_screen.dart';
import 'package:cotravel_app/features/logistics/domain/booking_search_links.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/domain/trip_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Trip _trip({
  String? occupation,
  int days = 6,
  String destination = 'Sidi Ifni',
}) {
  final start = DateTime(2026, 10, 2);
  return Trip(
    id: 'trip',
    hostId: 'host',
    hostName: 'Yasmine A.',
    hostHomeCity: null,
    hostVerified: true,
    hostOccupation: occupation,
    title: 'Atlas villages',
    originCity: 'Ait Ben Haddou',
    startDate: start,
    endDate: start.add(Duration(days: days)),
    stops: [TripStop(city: destination, arrivalDate: start)],
    capacity: 4,
    confirmedTravelerCount: 1,
    lodgingTotal: 100,
    transportTotal: 100,
    currency: 'MAD',
    travelStyle: 'Culture',
    summary: 'A summary that is long enough.',
  );
}

void main() {
  group('booking links', () {
    test('carry the place, dates and group size', () {
      final links = BookingSearchLinks.forTrip(_trip());

      expect(links.airbnb.pathSegments, ['s', 'Sidi Ifni', 'homes']);
      expect(links.airbnb.queryParameters, {
        'checkin': '2026-10-02',
        'checkout': '2026-10-08',
        'adults': '4',
      });
      expect(links.booking.queryParameters['ss'], 'Sidi Ifni');
      expect(links.booking.queryParameters['group_adults'], '4');
      expect(links.directions.queryParameters['origin'], 'Ait Ben Haddou');
      expect(links.directions.queryParameters['destination'], 'Sidi Ifni');
      expect(links.booking.toString(), contains('Sidi+Ifni'));
    });

    test('a one-day trip checks out the next day', () {
      final links = BookingSearchLinks.forTrip(_trip(days: 0));

      expect(links.booking.queryParameters['checkout'], '2026-10-03');
    });
  });

  group('place search', () {
    test('finds places by any part of the name, ignoring accents', () {
      expect(MoroccoRouteCoordinates.search('ben'), contains('Ait Ben Haddou'));
      expect(MoroccoRouteCoordinates.search('fès'), contains('Fes'));
      expect(MoroccoRouteCoordinates.lookup('Fès'), isNotNull);
    });

    test('puts names starting with the search first and caps the list', () {
      expect(MoroccoRouteCoordinates.search('ma').first, 'Marrakech');
      expect(MoroccoRouteCoordinates.search('a').length, lessThanOrEqualTo(6));
    });

    test('offers nothing for an empty search or an unknown place', () {
      expect(MoroccoRouteCoordinates.search(' '), isEmpty);
      expect(MoroccoRouteCoordinates.search('atlantis'), isEmpty);
    });
  });

  group('trip map', () {
    test('groups trips by destination and counts the unmappable', () {
      final result = TripMapPins.fromTrips([
        _trip(),
        _trip(destination: 'sidi ifni'),
        _trip(destination: 'Agadir'),
        _trip(destination: 'Atlantis'),
      ]);

      expect(result.pins.map((pin) => pin.place), ['Agadir', 'Sidi Ifni']);
      expect(result.pins.last.trips, hasLength(2));
      expect(result.unmappedCount, 1);
    });

    testWidgets('every pin can be reached without touching the map', (
      tester,
    ) async {
      TripMapPin? selected;
      final result = TripMapPins.fromTrips([
        _trip(),
        _trip(destination: 'Atlantis'),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TripPinsBar(
              result: result,
              onSelected: (pin) => selected = pin,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Sidi Ifni (1)'));
      expect(selected?.place, 'Sidi Ifni');
      expect(find.textContaining('no map location'), findsOneWidget);
    });
  });

  group('host background filter', () {
    test('matches the declared occupation', () {
      const filter = TripFilter(hostBackgroundQuery: 'design');

      expect(filter.isActive, isTrue);
      expect(filter.matches(_trip(occupation: 'Product Designer')), isTrue);
      expect(filter.matches(_trip(occupation: 'Teacher')), isFalse);
      expect(filter.matches(_trip()), isFalse);
    });
  });
}
