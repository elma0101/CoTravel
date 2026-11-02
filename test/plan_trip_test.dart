import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Future<ProviderContainer> _openPlanner(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  final authState = AppAuthState.preview(initiallyAuthenticated: true);
  addTearDown(authState.dispose);
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(
        const AppConfig(
          environment: AppEnvironment.development,
          supabaseUrl: '',
          supabasePublishableKey: '',
          requestPreviewAuth: true,
          requireLinkedInVerification: false,
        ),
      ),
      appAuthStateProvider.overrideWithValue(authState),
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const CoTravelApp()),
  );
  await tester.pumpAndSettle();
  GoRouter.of(
    tester.element(find.byType(Scaffold).first),
  ).push(AppRoutes.createTrip);
  await tester.pumpAndSettle();
  return container;
}

Future<void> _next(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('plan-next')));
  await tester.pumpAndSettle();
}

Trip _newest(ProviderContainer container) {
  return container
      .read(tripCatalogProvider)
      .hostedTrips
      .firstWhere((trip) => trip.id.startsWith('preview-created'));
}

void main() {
  testWidgets('a trip is published by tapping, with only the destination', (
    tester,
  ) async {
    final container = await _openPlanner(tester);

    expect(find.text('Where are you going?'), findsOneWidget);
    // The departure starts at the host's home city.
    expect(find.text('Casablanca'), findsOneWidget);
    await tester.tap(find.text('Merzouga'));
    await tester.pump();
    await _next(tester);

    expect(find.text('When?'), findsOneWidget);
    await tester.tap(find.text('Long weekend'));
    await tester.pump();
    expect(find.text('4 days'), findsOneWidget);
    await _next(tester);

    await tester.tap(find.byKey(const ValueKey('trip-capacity-more')));
    await tester.pump();
    expect(find.text('You + 4 travelers'), findsOneWidget);
    await _next(tester);

    expect(find.text('What will it cost each person?'), findsOneWidget);
    await _next(tester);

    expect(find.text('Looking good!'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-title')),
      300,
      scrollable: find
          .ancestor(
            of: find.text('Looking good!'),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    final title = tester.widget<TextField>(
      find.byKey(const ValueKey('trip-title')),
    );
    expect(title.controller!.text, 'Long weekend in Merzouga');
    await tester.tap(find.byKey(const ValueKey('publish-trip')));
    await tester.pumpAndSettle();

    expect(find.text('Your trip is live!'), findsOneWidget);
    final trip = _newest(container);
    expect(trip.title, 'Long weekend in Merzouga');
    expect(trip.originCity, 'Casablanca');
    expect(trip.destinationCity, 'Merzouga');
    expect(trip.capacity, 5);
    expect(trip.durationDays, 4);
    expect(trip.startDate.weekday, DateTime.friday);
    // The default 400 + 200 per person, for the whole group.
    expect(trip.lodgingTotal, 2000);
    expect(trip.transportTotal, 1000);
    expect(trip.estimatedFullGroupShare, 600);
    expect(trip.summary, contains('Casablanca'));
  });

  testWidgets('stops on the way come before the destination', (tester) async {
    final container = await _openPlanner(tester);

    await tester.enterText(
      find.byKey(const ValueKey('trip-destination')),
      'Merzouga',
    );
    await tester.tap(find.byKey(const ValueKey('trip-add-via')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('plan-next')))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.byKey(const ValueKey('trip-via-0')),
      'Ouarzazate',
    );
    await tester.pump();
    for (var step = 0; step < 4; step++) {
      await _next(tester);
    }
    await tester.tap(find.byKey(const ValueKey('publish-trip')));
    await tester.pumpAndSettle();

    final trip = _newest(container);
    expect(trip.stops.map((stop) => stop.city), ['Ouarzazate', 'Merzouga']);
    expect(
      trip.stops.every(
        (stop) =>
            !stop.arrivalDate.isBefore(trip.startDate) &&
            !stop.arrivalDate.isAfter(trip.endDate),
      ),
      isTrue,
    );
    expect(
      trip.stops.last.arrivalDate.isBefore(trip.stops.first.arrivalDate),
      isFalse,
    );
  });

  testWidgets('back keeps every answer', (tester) async {
    await _openPlanner(tester);

    await tester.tap(find.text('Essaouira'));
    await tester.pump();
    await _next(tester);
    await _next(tester);
    await tester.tap(find.byKey(const ValueKey('trip-capacity-more')));
    await tester.pump();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('When?'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Where are you going?'), findsOneWidget);
    final destination = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('trip-destination')),
        matching: find.byType(TextField),
      ),
    );
    expect(destination.controller!.text, 'Essaouira');
  });
}
