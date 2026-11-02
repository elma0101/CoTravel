import 'package:cotravel_app/features/logistics/domain/booking_search_links.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/domain/trip_route.dart';
import 'package:flutter_test/flutter_test.dart';

Trip _trip({String? occupation, int days = 6}) {
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
    stops: [TripStop(city: 'Sidi Ifni', arrivalDate: start)],
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
