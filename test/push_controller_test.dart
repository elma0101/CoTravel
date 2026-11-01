import 'dart:async';

import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/features/notifications/application/push_controller.dart';
import 'package:cotravel_app/features/notifications/data/push_messaging.dart';
import 'package:cotravel_app/features/notifications/domain/app_notification.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeMessaging implements PushMessaging {
  _FakeMessaging({
    this.available = true,
    this.permitted = true,
    this.launchData,
  });

  final bool available;
  final bool permitted;
  final Map<String, String>? launchData;
  final refreshes = StreamController<String>.broadcast();
  final opens = StreamController<Map<String, String>>.broadcast();
  final log = <String>[];
  int _generation = 0;

  @override
  Future<bool> initialize() async => available;

  @override
  Future<bool> requestPermission() async => permitted;

  @override
  Future<String?> getToken() async => 'token-$_generation';

  @override
  Future<void> deleteToken() async {
    _generation++;
    log.add('delete');
  }

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<Map<String, String>> get openedMessages => opens.stream;

  @override
  Future<Map<String, String>?> initialMessage() async => launchData;
}

class _FakeTokens implements PushTokenRepository {
  final registered = <String>[];
  bool fails = false;

  @override
  Future<void> register(String token) async {
    if (fails) {
      throw StateError('offline');
    }
    registered.add(token);
  }
}

void main() {
  late _FakeTokens tokens;

  setUp(() => tokens = _FakeTokens());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  PushController controllerFor(
    AppAuthState authState,
    _FakeMessaging messaging,
  ) {
    final controller = PushController(
      authState: authState,
      messaging: messaging,
      tokens: tokens,
    );
    addTearDown(controller.dispose);
    return controller;
  }

  test('registers the device when the user is signed in', () async {
    final auth = AppAuthState.preview(initiallyAuthenticated: true);
    await controllerFor(auth, _FakeMessaging()).start();
    await settle();

    expect(tokens.registered, ['token-0']);
  });

  test('does nothing without Firebase configuration', () async {
    final auth = AppAuthState.preview(initiallyAuthenticated: true);
    final messaging = _FakeMessaging(available: false);
    await controllerFor(auth, messaging).start();
    await settle();

    expect(tokens.registered, isEmpty);
    expect(messaging.log, isEmpty);
  });

  test('does not register when permission is refused', () async {
    final auth = AppAuthState.preview(initiallyAuthenticated: true);
    await controllerFor(auth, _FakeMessaging(permitted: false)).start();
    await settle();

    expect(tokens.registered, isEmpty);
  });

  test(
    'signing out revokes the token, and the next user gets a new one',
    () async {
      final auth = AppAuthState.preview(initiallyAuthenticated: true);
      final messaging = _FakeMessaging();
      await controllerFor(auth, messaging).start();
      await settle();

      await auth.signOut();
      await settle();
      expect(messaging.log, ['delete']);

      await auth.signInForPreview();
      await settle();
      expect(tokens.registered, ['token-0', 'token-1']);
    },
  );

  test('a failed registration does not stop later token updates', () async {
    final auth = AppAuthState.preview(initiallyAuthenticated: true);
    final messaging = _FakeMessaging();
    tokens.fails = true;
    await controllerFor(auth, messaging).start();
    await settle();

    tokens.fails = false;
    messaging.refreshes.add('refreshed');
    await settle();

    expect(tokens.registered, ['refreshed']);
  });

  test('ignores a token refresh while signed out', () async {
    final auth = AppAuthState.preview();
    final messaging = _FakeMessaging();
    await controllerFor(auth, messaging).start();
    await settle();

    messaging.refreshes.add('refreshed');
    await settle();

    expect(tokens.registered, isEmpty);
  });

  test('holds a tapped notification until the user is signed in', () async {
    final auth = AppAuthState.preview();
    final opened = <PushOpen>[];
    final controller = controllerFor(
      auth,
      _FakeMessaging(launchData: {'kind': 'trip_cancelled'}),
    )..attach(opened.add);
    await controller.start();
    expect(opened, isEmpty);

    await auth.signInForPreview();
    expect(opened.single.kind, 'trip_cancelled');
  });

  group('opening a notification', () {
    Future<(ProviderContainer, _FakeMessaging)> pumpApp(
      WidgetTester tester,
    ) async {
      final messaging = _FakeMessaging();
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
          appAuthStateProvider.overrideWithValue(
            AppAuthState.preview(initiallyAuthenticated: true),
          ),
          pushMessagingProvider.overrideWithValue(messaging),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const CoTravelApp(),
        ),
      );
      await tester.pumpAndSettle();
      return (container, messaging);
    }

    String location(ProviderContainer container) {
      return container
          .read(appRouterProvider)
          .routerDelegate
          .currentConfiguration
          .last
          .matchedLocation;
    }

    testWidgets('a join request goes to the requests screen', (tester) async {
      final (container, messaging) = await pumpApp(tester);

      messaging.opens.add({
        'kind': 'join_request_received',
        'trip_id': 'atlas-weekend',
      });
      await tester.pumpAndSettle();

      expect(location(container), AppRoutes.tripRequests('atlas-weekend'));
    });

    testWidgets('an unknown kind falls back to the inbox', (tester) async {
      final (container, messaging) = await pumpApp(tester);

      messaging.opens.add({'kind': 'from_a_newer_server'});
      await tester.pumpAndSettle();

      expect(location(container), AppRoutes.notifications);
    });

    testWidgets('marks the notification read', (tester) async {
      final (container, messaging) = await pumpApp(tester);
      final notifications = container.read(notificationControllerProvider);
      await tester.runAsync(notifications.load);
      final unread = notifications.unreadCount;

      messaging.opens.add({'notification_id': 'preview-notification-request'});
      await tester.pumpAndSettle();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));

      expect(notifications.unreadCount, unread - 1);
    });
  });

  test('every stored kind has a route when it has a trip', () {
    for (final kind in NotificationKind.values) {
      expect(AppRoutes.notificationTarget(kind, 'trip'), isNotNull);
      expect(AppRoutes.notificationTarget(kind, null), isNull);
    }
  });
}
