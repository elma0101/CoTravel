import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ProviderContainer> _pumpExplore(WidgetTester tester) async {
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
  return container;
}

String _topTripId(WidgetTester tester) {
  final key = tester
      .widgetList(find.byWidgetPredicate((widget) => widget is GestureDetector))
      .map((widget) => widget.key)
      .whereType<ValueKey<String>>()
      .firstWhere((key) => key.value.startsWith('swipe-card-'));
  return key.value.substring('swipe-card-'.length);
}

void main() {
  testWidgets('swiping right saves a trip and shows the next one', (
    tester,
  ) async {
    final container = await _pumpExplore(tester);
    final catalog = container.read(tripCatalogProvider);
    final first = _topTripId(tester);
    expect(catalog.isSaved(first), isFalse);

    await tester.drag(
      find.byKey(ValueKey('swipe-card-$first')),
      const Offset(400, 0),
    );
    await tester.pumpAndSettle();

    expect(catalog.isSaved(first), isTrue);
    expect(_topTripId(tester), isNot(first));
    expect(find.text('Saved. Find it in My trips.'), findsOneWidget);
  });

  testWidgets('swiping left skips without saving, and undo brings it back', (
    tester,
  ) async {
    final container = await _pumpExplore(tester);
    final catalog = container.read(tripCatalogProvider);
    final first = _topTripId(tester);

    await tester.drag(
      find.byKey(ValueKey('swipe-card-$first')),
      const Offset(-400, 0),
    );
    await tester.pumpAndSettle();
    expect(catalog.isSaved(first), isFalse);
    expect(_topTripId(tester), isNot(first));

    await tester.tap(find.byKey(const ValueKey('swipe-undo')));
    await tester.pumpAndSettle();
    expect(_topTripId(tester), first);
  });

  testWidgets('a short drag springs back to the same trip', (tester) async {
    await _pumpExplore(tester);
    final first = _topTripId(tester);

    await tester.drag(
      find.byKey(ValueKey('swipe-card-$first')),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();

    expect(_topTripId(tester), first);
  });

  testWidgets('the end of the deck offers to start over', (tester) async {
    final container = await _pumpExplore(tester);
    final count = container.read(tripCatalogProvider).discoverableTrips.length;

    for (var index = 0; index < count; index++) {
      await tester.tap(find.byKey(const ValueKey('swipe-skip')));
      await tester.pumpAndSettle();
    }
    expect(find.text('You have seen every trip'), findsOneWidget);

    await tester.tap(find.text('Start over'));
    await tester.pumpAndSettle();
    expect(find.text('1 of $count'), findsOneWidget);
  });

  testWidgets('a style chip filters at once and Clear resets it', (
    tester,
  ) async {
    final container = await _pumpExplore(tester);
    final catalog = container.read(tripCatalogProvider);
    final all = catalog.discoverableTrips.length;

    final chips = find.descendant(
      of: find.byKey(const ValueKey('explore-filter-chips')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(find.text('Food'), 120, scrollable: chips);
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(catalog.filter.travelStyle, 'Food');
    expect(
      catalog.discoverableTrips.every((trip) => trip.travelStyle == 'Food'),
      isTrue,
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('filter-clear')),
      200,
      scrollable: chips,
    );
    await tester.tap(find.byKey(const ValueKey('filter-clear')));
    await tester.pumpAndSettle();
    expect(catalog.discoverableTrips.length, all);
  });

  testWidgets('the list view still shows every trip', (tester) async {
    await _pumpExplore(tester);

    await tester.tap(find.byKey(const ValueKey('explore-toggle-view')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('explore-list')), findsOneWidget);
  });
}
