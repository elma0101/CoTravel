import 'package:cotravel_app/app/theme/app_colors.dart';
import 'package:cotravel_app/app/theme/app_theme.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/mountain_illustration.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/trip_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Trip _trip({int capacity = 4, int confirmed = 1}) {
  final start = DateTime(2026, 10, 12);
  return Trip(
    id: 'custom-trip',
    hostId: 'host',
    hostName: 'Yasmine A.',
    hostHomeCity: null,
    hostVerified: true,
    title: 'Atlas villages',
    originCity: 'Marrakech',
    startDate: start,
    endDate: start.add(const Duration(days: 6)),
    stops: [
      TripStop(city: 'Ait Benhaddou', arrivalDate: start),
      TripStop(city: 'Merzouga', arrivalDate: start),
    ],
    capacity: capacity,
    confirmedTravelerCount: confirmed,
    lodgingTotal: 100,
    transportTotal: 100,
    currency: 'MAD',
    travelStyle: 'Culture',
    summary: 'A summary that is long enough.',
  );
}

Future<void> _pumpCard(WidgetTester tester, Trip trip) {
  return tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TripCard(trip: trip, onTap: () {}),
        ),
      ),
    ),
  );
}

void main() {
  test('primary buttons are filled green', () {
    final style = AppTheme.light.elevatedButtonTheme.style!;
    expect(style.backgroundColor!.resolve({}), AppColors.green);
    expect(style.foregroundColor!.resolve({}), Colors.white);
  });

  testWidgets('a trip card shows the route, host, and seats', (tester) async {
    await _pumpCard(tester, _trip());

    expect(find.text('Marrakech → Ait Benhaddou → Merzouga'), findsOneWidget);
    expect(find.text('2 seats left'), findsOneWidget);
    expect(find.text('Yasmine A.'), findsOneWidget);
    expect(find.text('LinkedIn verified'), findsOneWidget);
    expect(find.text('estimated'), findsOneWidget);
  });

  testWidgets('a trip without a photo uses the illustration', (tester) async {
    await _pumpCard(tester, _trip());

    expect(find.byType(MountainIllustration), findsOneWidget);
  });

  testWidgets('a full trip says so', (tester) async {
    await _pumpCard(tester, _trip(capacity: 2));

    expect(find.text('Full'), findsOneWidget);
  });
}
