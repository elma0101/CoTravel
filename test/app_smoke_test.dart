import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/core/analytics/product_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('guards app routes while signed out', (tester) async {
    final authState = AppAuthState.preview();
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);

    expect(find.text('Travel better,\ntogether.'), findsOneWidget);
    expect(find.text('Preview the app'), findsOneWidget);
    expect(find.text('Explore'), findsNothing);
  });

  testWidgets('enters the app from development preview', (tester) async {
    final authState = AppAuthState.preview();
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.text('Preview the app'));
    await tester.pumpAndSettle();

    expect(find.text('CoTravel'), findsOneWidget);
    expect(find.text('Find your people,\nthen go.'), findsOneWidget);
    expect(find.text('Explore'), findsOneWidget);
  });

  testWidgets('switches between protected destinations', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.luggage_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Rif towns and trails'), findsOneWidget);
    expect(find.text('1 new request to review'), findsOneWidget);
  });

  testWidgets('filters discovery and opens a trip detail', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Essaouira',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();

    expect(find.text('1 matching trips'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Coast, food, and surf'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Coast, food, and surf'));
    await tester.pumpAndSettle();

    expect(find.text('Trip details'), findsOneWidget);
    expect(find.text('Route'), findsOneWidget);
    expect(find.text('Rabat to Essaouira'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('host-actions-host-youssef')),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('host-actions-host-youssef')));
    await tester.pumpAndSettle();

    expect(find.text('Message'), findsOneWidget);
    expect(
      find.text('Available after your place on this trip is confirmed.'),
      findsOneWidget,
    );
    final lockedMessageAction = tester.widget<InkWell>(
      find.descendant(
        of: find.byKey(const ValueKey('message-user-host-youssef')),
        matching: find.byType(InkWell),
      ),
    );
    expect(lockedMessageAction.onTap, isNull);
  });

  testWidgets('traveler confirms a host-approved request', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Imlil',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Atlas villages weekend'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Atlas villages weekend'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('confirm-trip-place')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-trip-place')));
    await tester.pumpAndSettle();

    expect(find.text('Your place is confirmed'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('2 places left'),
      -320,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('2 places left'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Atlas villages weekend'), findsOneWidget);
  });

  testWidgets('opens a confirmed group chat and sends a message', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Dades slow road'), findsOneWidget);
    expect(
      find.text('I will share the guesthouse shortlist tonight.'),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('conversation-preview-conversation-dades')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Only confirmed trip members can read this conversation.'),
      findsOneWidget,
    );
    expect(find.text('Yes, any time after 7 works for me.'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-composer')),
      'I can compare the two guesthouses after dinner.',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('send-chat-message')));
    await tester.pumpAndSettle();

    expect(
      find.text('I can compare the two guesthouses after dinner.'),
      findsOneWidget,
    );
  });

  testWidgets('host actions connect trip details, profile, and group chat', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Boumalne',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dades slow road'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Dades slow road'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('host-actions-host-leila')),
      360,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('host-actions-host-leila')));
    await tester.pumpAndSettle();

    expect(find.text('View profile'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-profile-host-leila')));
    await tester.pumpAndSettle();

    expect(find.text('Traveler profile'), findsOneWidget);
    expect(find.text('Leila M.'), findsOneWidget);
    expect(find.text('Slow travel'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-message-host-leila')));
    await tester.pumpAndSettle();

    expect(
      find.text('Only confirmed trip members can read this conversation.'),
      findsOneWidget,
    );
  });

  testWidgets('chat sender opens the same traveler profile', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.chat_bubble_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('conversation-preview-conversation-dades')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('chat-user-host-leila-preview-host-shortlist')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Back to trip chat'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-profile-host-leila')));
    await tester.pumpAndSettle();
    expect(find.text('Traveler profile'), findsOneWidget);
    expect(find.text('Leila M.'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('profile-message-host-leila')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('chat-composer')), findsOneWidget);
  });

  testWidgets('confirmed traveler explores dynamic shared costs', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Boumalne',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Dades slow road'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Dades slow road'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-shared-logistics')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('open-shared-logistics')));
    await tester.pumpAndSettle();

    expect(find.text('3 confirmed in the group'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('group-size-slider')),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(
      find.byKey(const ValueKey('group-size-slider')),
      const Offset(500, 0),
    );
    await tester.pumpAndSettle();

    expect(find.text('5 people'), findsOneWidget);
    expect(find.text('1,480 MAD'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('accommodation-booking-link')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Dades guesthouse shortlist'), findsOneWidget);
  });

  testWidgets('host updates shared logistics from a hosted trip', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.luggage_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rif towns and trails'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-shared-logistics')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const ValueKey('open-shared-logistics')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('edit-logistics')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('logistics-lodging-total')),
      '4200',
    );
    await tester.enterText(
      find.byKey(const ValueKey('logistics-transport-total')),
      '1800',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('save-logistics')),
      320,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('save-logistics')));
    await tester.pumpAndSettle();

    expect(find.text('Shared logistics updated.'), findsOneWidget);
    expect(find.textContaining('6,000 MAD each today'), findsOneWidget);
  });

  testWidgets('traveler reports, blocks, and later unblocks a host', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-origin')),
      'Tangier',
    );
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Tetouan',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Northern colors'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Northern colors'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('safety-options-host-salma')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('safety-options-host-salma')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('safety-report-details')),
      'The meeting instructions include an unsafe and isolated pickup point.',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Also block this person'),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byType(Checkbox));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('submit-safety-report')),
      220,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.byKey(const ValueKey('submit-safety-report')));
    await tester.pumpAndSettle();

    expect(find.text('Northern colors'), findsNothing);
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-safety-center')));
    await tester.pumpAndSettle();

    expect(find.text('Safety Center'), findsOneWidget);
    expect(find.text('Salma R.'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('unblock-host-salma')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('confirm-unblock-host-salma')));
    await tester.pumpAndSettle();

    expect(find.text('You have not blocked anyone.'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Harassment or intimidation'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Submitted'), findsOneWidget);
    expect(find.text('Salma R.'), findsOneWidget);
  });

  testWidgets('Safety Center meets Android tap-target guidance', (
    tester,
  ) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-safety-center')));
    await tester.pumpAndSettle();

    expect(find.text('Safety Center'), findsOneWidget);
    expect(tester, meetsGuideline(androidTapTargetGuideline));
  });

  testWidgets('host approves a candidate after profile review', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.luggage_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pending-host-requests')));
    await tester.pumpAndSettle();

    expect(find.text('Nadia K.'), findsOneWidget);
    expect(find.textContaining('Museum lover'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('approve-request-preview-nadia-request')),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Approved by you. Waiting for the traveler to confirm.'),
      findsOneWidget,
    );
  });

  testWidgets('sends a new join request with an introduction', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.enterText(
      find.byKey(const ValueKey('explore-origin')),
      'Tangier',
    );
    await tester.enterText(
      find.byKey(const ValueKey('explore-destination')),
      'Tetouan',
    );
    await tester.tap(find.text('Find trips'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Northern colors'),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Northern colors'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('request-to-join')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -140));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('request-to-join')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('join-request-message')),
      'I enjoy cultural weekends and would be glad to share the planning.',
    );
    tester.testTextInput.hide();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('send-join-request')));
    await tester.tap(find.byKey(const ValueKey('send-join-request')));
    await tester.pumpAndSettle();

    expect(find.text('Request sent to the host.'), findsOneWidget);
  });

  testWidgets('creates an itinerary in preview mode', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    final analytics = PreviewProductAnalytics();
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState, analytics: analytics);
    await tester.tap(find.byIcon(Icons.luggage_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-trip')));
    await tester.pumpAndSettle();

    expect(analytics.events.single.event, ProductEvent.tripBuilderOpened);

    await tester.enterText(
      find.byKey(const ValueKey('trip-title')),
      'Desert night skies',
    );
    await tester.enterText(
      find.byKey(const ValueKey('trip-origin')),
      'Ouarzazate',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-stop-city-0')),
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('trip-stop-city-0')),
      'Erg Chigaga',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-lodging')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const ValueKey('trip-lodging')), '3200');
    await tester.enterText(find.byKey(const ValueKey('trip-transport')), '800');
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('trip-summary')),
      320,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const ValueKey('trip-summary')),
      'Two quiet nights focused on desert landscapes and clear skies.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('publish-trip')),
      280,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('publish-trip')));
    await tester.pumpAndSettle();

    expect(find.text('My trips'), findsWidgets);
    expect(find.text('Desert night skies'), findsOneWidget);
    expect(find.text('Ouarzazate to Erg Chigaga'), findsOneWidget);
    expect(analytics.events.last.event, ProductEvent.tripPublished);
  });

  testWidgets('requires and completes profile onboarding', (tester) async {
    final authState = AppAuthState.preview(
      initiallyAuthenticated: true,
      onboardingComplete: false,
    );
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);

    expect(
      find.text('Help people know who they will travel with.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Display name'),
      'Sam Traveler',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Short introduction'),
      'I enjoy thoughtful itineraries and meeting considerate travelers.',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Home city'),
      'Casablanca',
    );
    await tester.drag(find.byType(ListView), const Offset(0, -480));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Culture'));
    await tester.scrollUntilVisible(
      find.text('Languages'),
      240,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Languages'),
      'Arabic, French',
    );
    await tester.ensureVisible(find.text('Complete profile'));
    await tester.tap(find.text('Complete profile'));
    await tester.pumpAndSettle();

    expect(find.text('Find your people,\nthen go.'), findsOneWidget);
  });

  testWidgets('returns to welcome after signing out', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -280));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.logout_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Travel better,\ntogether.'), findsOneWidget);
  });

  testWidgets('beta tester submits safe-and-informed feedback', (tester) async {
    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    addTearDown(authState.dispose);

    await _pumpApp(tester, authState);
    await tester.tap(find.byIcon(Icons.person_outline_rounded));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('open-beta-feedback')),
      220,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('open-beta-feedback')));
    await tester.pumpAndSettle();

    expect(
      find.text('Did CoTravel help you feel safe and informed?'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('beta-score-4')));
    await tester.drag(find.byType(ListView), const Offset(0, -320));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('beta-comments')),
      'The confirmation steps made the group status easy to understand.',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('submit-beta-feedback')),
    );
    await tester.tap(find.byKey(const ValueKey('submit-beta-feedback')));
    await tester.pumpAndSettle();

    expect(find.text('Thank you'), findsOneWidget);
    expect(
      find.text('Your response is part of the controlled-beta readout.'),
      findsOneWidget,
    );
  });
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppAuthState authState, {
  ProductAnalytics? analytics,
}) async {
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
        appAuthStateProvider.overrideWithValue(authState),
        if (analytics != null)
          productAnalyticsProvider.overrideWithValue(analytics),
      ],
      child: const CoTravelApp(),
    ),
  );
  await tester.pumpAndSettle();
}
