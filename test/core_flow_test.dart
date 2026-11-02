import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/features/notifications/application/notification_controller.dart';
import 'package:cotravel_app/features/notifications/data/notification_repository.dart';
import 'package:cotravel_app/features/notifications/domain/app_notification.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  group('cancellation window', () {
    final now = DateTime(2026, 6, 10, 15);

    Trip tripStarting(DateTime start) {
      return Trip(
        id: 'trip',
        hostId: 'host',
        hostName: 'Host',
        hostHomeCity: null,
        hostVerified: true,
        title: 'Trip',
        originCity: 'Rabat',
        startDate: start,
        endDate: start.add(const Duration(days: 2)),
        stops: [TripStop(city: 'Fes', arrivalDate: start)],
        capacity: 4,
        confirmedTravelerCount: 1,
        lodgingTotal: 100,
        transportTotal: 100,
        currency: 'MAD',
        travelStyle: 'Culture',
        summary: 'A summary that is long enough.',
      );
    }

    test('is free through the seventh day before departure', () {
      expect(tripStarting(DateTime(2026, 6, 17)).isLateToLeave(now), isFalse);
    });

    test('is late from the sixth day before departure', () {
      expect(tripStarting(DateTime(2026, 6, 16)).isLateToLeave(now), isTrue);
    });

    test('counts the departure day as not yet started', () {
      expect(tripStarting(DateTime(2026, 6, 10)).hasStarted(now), isFalse);
      expect(tripStarting(DateTime(2026, 6, 9)).hasStarted(now), isTrue);
    });
  });

  test('preview discovery hides cancelled trips', () async {
    final repository = PreviewTripRepository();
    final before = await repository.discoverTrips();
    await repository.cancelTrip(before.first.id);

    final after = await repository.discoverTrips();

    expect(after.map((trip) => trip.id), isNot(contains(before.first.id)));
  });

  test('marking a notification read lowers the unread count', () async {
    final controller = NotificationController(
      repository: PreviewNotificationRepository(),
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.unreadCount, 2);

    await controller.markRead(controller.notifications.first);
    expect(controller.unreadCount, 1);

    await controller.markAllRead();
    expect(controller.unreadCount, 0);
  });

  test('every notification kind round-trips through storage', () {
    for (final kind in NotificationKind.values) {
      expect(NotificationKind.fromStorage(kind.storageValue), kind);
    }
    expect(NotificationKind.fromStorage('future_kind'), isNull);
  });

  testWidgets('the bell shows unread notifications and opens the inbox', (
    tester,
  ) async {
    await _pumpApp(tester);

    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-notifications')));
    await tester.pumpAndSettle();

    expect(
      find.text('Nadia K. asked to join Rif towns and trails.'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('mark-all-notifications-read')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mark-all-notifications-read')),
      findsNothing,
    );
  });

  testWidgets('a notification opens the matching request inbox', (
    tester,
  ) async {
    await _pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('open-notifications')));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('notification-preview-notification-request')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Traveler requests'), findsOneWidget);
  });

  testWidgets('a host edits a trip and keeps its route', (tester) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.tripDetails('preview-rif-loop'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const ValueKey('edit-trip'));
    await tester.tap(find.byKey(const ValueKey('edit-trip')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Edit trip'), findsOneWidget);
    expect(find.text('Rif towns and trails'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('trip-title')),
      'Rif loop revised',
    );
    await tester.tap(find.byKey(const ValueKey('publish-trip')));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'Trip details'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Rif loop revised'),
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Rif loop revised'), findsOneWidget);
  });

  testWidgets('a host cancels a trip after confirming', (tester) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.tripDetails('preview-rif-loop'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const ValueKey('cancel-trip'));
    await tester.tap(find.byKey(const ValueKey('cancel-trip')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('confirm-cancel-trip')));
    await tester.pumpAndSettle();

    await _scrollToFinder(tester, find.text('This trip was cancelled'));
    expect(find.text('This trip was cancelled'), findsOneWidget);
    expect(find.byKey(const ValueKey('edit-trip')), findsNothing);
  });

  testWidgets('a confirmed traveler leaves and sees the free window', (
    tester,
  ) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.tripDetails('dades-slow-road'));
    await tester.pumpAndSettle();
    await _scrollTo(tester, const ValueKey('leave-trip'));
    await tester.tap(find.byKey(const ValueKey('leave-trip')));
    await tester.pumpAndSettle();

    expect(find.textContaining('You can leave freely until'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('confirm-leave-trip')));
    await tester.pumpAndSettle();

    await _scrollTo(tester, const ValueKey('request-to-join'));
    expect(find.byKey(const ValueKey('request-to-join')), findsOneWidget);
  });

  testWidgets('a saved trip appears under My trips', (tester) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.tripDetails('dades-slow-road'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('save-trip')));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.bookmark_rounded), findsOneWidget);

    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).go(AppRoutes.trips);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('saved-trips-tab')));
    await tester.pumpAndSettle();

    expect(find.text('Dades slow road'), findsOneWidget);
  });

  testWidgets('a host sees useful context and the cost if someone joins', (
    tester,
  ) async {
    await _pumpApp(tester);
    _go(tester, AppRoutes.tripRequests('preview-rif-loop'));
    await tester.pumpAndSettle();

    expect(find.text('Useful context'), findsOneWidget);
    expect(find.text('Free for all the dates'), findsOneWidget);
    expect(find.text('Arabic, French, English'), findsOneWidget);
    expect(find.text('Driving licence not checked'), findsOneWidget);
    expect(find.byKey(const ValueKey('cost-if-joins')), findsOneWidget);
  });

  testWidgets('a traveler edits their profile and stays in the app', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    await _pumpApp(tester, authState: authState);
    await tester.tap(find.text('Profile'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-edit-profile')));
    await tester.pumpAndSettle();

    expect(find.text('Edit profile'), findsOneWidget);
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Renamed traveler',
    );
    await _scrollTo(tester, const ValueKey('save-profile'));
    await tester.tap(find.byKey(const ValueKey('save-profile')));
    await tester.pumpAndSettle();

    expect(authState.status, AppSessionStatus.authenticated);
    expect(authState.profile?.displayName, 'Renamed traveler');
    expect(find.text('Renamed traveler'), findsOneWidget);
    expect(find.byKey(const ValueKey('open-edit-profile')), findsOneWidget);
  });
}

void _go(WidgetTester tester, String location) {
  GoRouter.of(tester.element(find.byType(Scaffold).first)).push(location);
}

Future<void> _scrollTo(WidgetTester tester, Key key) {
  return _scrollToFinder(tester, find.byKey(key));
}

Future<void> _scrollToFinder(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpApp(WidgetTester tester, {AppAuthState? authState}) async {
  tester.view
    ..physicalSize = const Size(1170, 2532)
    ..devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  const config = AppConfig(
    environment: AppEnvironment.development,
    supabaseUrl: '',
    supabasePublishableKey: '',
    requestPreviewAuth: true,
    requireLinkedInVerification: false,
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
        appAuthStateProvider.overrideWithValue(
          authState ?? AppAuthState.preview(initiallyAuthenticated: true),
        ),
      ],
      child: const CoTravelApp(),
    ),
  );
  await tester.pumpAndSettle();
}
