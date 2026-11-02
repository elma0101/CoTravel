import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/features/legal/domain/legal_documents.dart';
import 'package:cotravel_app/features/profile/data/profile_repository.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// A finished profile whose LinkedIn status the test controls.
class _MemberRepository extends PreviewProfileRepository {
  bool verified = false;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    return UserProfile(
      id: userId,
      displayName: 'Sam',
      bio: null,
      homeCity: null,
      avatarUrl: null,
      travelStyles: const ['Culture'],
      languages: const ['French'],
      isLinkedInVerified: verified,
      isOnboardingComplete: true,
      acceptedTermsVersion: currentTermsVersion,
    );
  }

  @override
  Future<bool> syncLinkedInVerification(String userId) async => verified;
}

Future<void> _pumpApp(
  WidgetTester tester,
  AppAuthState authState, {
  bool requireLinkedIn = false,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(
          AppConfig(
            environment: AppEnvironment.development,
            supabaseUrl: '',
            supabasePublishableKey: '',
            requestPreviewAuth: true,
            requireLinkedInVerification: requireLinkedIn,
          ),
        ),
        appAuthStateProvider.overrideWithValue(authState),
      ],
      child: const CoTravelApp(),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _continue(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('setup-continue')));
  await tester.pumpAndSettle();
}

FilledButton _continueButton(WidgetTester tester) {
  return tester.widget<FilledButton>(
    find.byKey(const ValueKey('setup-continue')),
  );
}

Future<AppAuthState> _memberState(_MemberRepository repository) async {
  final authState = AppAuthState(
    supabaseClient: null,
    profileRepository: repository,
    previewAuthEnabled: true,
    authRedirectUrl: 'com.cotravel.app://login-callback',
  );
  await authState.synchronizeUser('user-1');
  return authState;
}

void main() {
  testWidgets('a new member signs up typing only their name', (tester) async {
    final authState = AppAuthState.preview(
      initiallyAuthenticated: true,
      onboardingComplete: false,
    );
    addTearDown(authState.dispose);
    await _pumpApp(tester, authState);

    expect(find.text('Hi! What should we call you?'), findsOneWidget);
    expect(_continueButton(tester).onPressed, isNull);
    await tester.enterText(find.byKey(const ValueKey('setup-name')), 'Sam');
    await tester.pump();
    await _continue(tester);

    expect(find.text('Where are you based?'), findsOneWidget);
    await tester.tap(find.text('Rabat'));
    await _continue(tester);

    expect(find.text('How do you like to travel?'), findsOneWidget);
    expect(_continueButton(tester).onPressed, isNull);
    await tester.tap(find.text('Nature'));
    await tester.tap(find.text('Food'));
    await tester.pump();
    await _continue(tester);

    expect(find.text('Which languages do you speak?'), findsOneWidget);
    await tester.tap(find.text('French'));
    await tester.pump();
    await _continue(tester);

    expect(find.text("You're in, Sam!"), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finish-setup')));
    await tester.pumpAndSettle();

    expect(find.text('Find your people, then go.'), findsOneWidget);
    final profile = authState.profile!;
    expect(profile.displayName, 'Sam');
    expect(profile.homeCity, 'Rabat');
    expect(profile.travelStyles, unorderedEquals(['Nature', 'Food']));
    expect(profile.languages, ['French']);
    expect(profile.hasAcceptedCurrentTerms, isTrue);
  });

  testWidgets('the home city can be skipped and back keeps the answers', (
    tester,
  ) async {
    final authState = AppAuthState.preview(
      initiallyAuthenticated: true,
      onboardingComplete: false,
    );
    addTearDown(authState.dispose);
    await _pumpApp(tester, authState);

    await tester.enterText(find.byKey(const ValueKey('setup-name')), 'Sam');
    await tester.pump();
    await _continue(tester);
    await tester.tap(find.byKey(const ValueKey('setup-skip')));
    await tester.pumpAndSettle();
    expect(find.text('How do you like to travel?'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.text('Hi! What should we call you?'), findsOneWidget);
    expect(find.text('Sam'), findsOneWidget);
  });

  testWidgets('hosting asks for LinkedIn once, then carries on', (
    tester,
  ) async {
    final repository = _MemberRepository();
    final authState = await _memberState(repository);
    addTearDown(authState.dispose);
    await _pumpApp(tester, authState, requireLinkedIn: true);

    await tester.tap(find.text('My trips'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('plan-trip')));
    await tester.pumpAndSettle();
    expect(find.text('One quick step before you host'), findsOneWidget);

    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('trip-title')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('plan-trip')));
    await tester.pumpAndSettle();
    // What the app sees once LinkedIn sends the member back.
    repository.verified = true;
    await authState.synchronizeUser('user-1');
    await tester.pump();
    expect(find.text('You are verified!'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(const ValueKey('trip-title')), findsOneWidget);
  });

  testWidgets('a verified member joins without being asked again', (
    tester,
  ) async {
    final repository = _MemberRepository()..verified = true;
    final authState = await _memberState(repository);
    addTearDown(authState.dispose);
    await _pumpApp(tester, authState, requireLinkedIn: true);

    GoRouter.of(
      tester.element(find.byType(Scaffold).first),
    ).push(AppRoutes.tripDetails('atlas-weekend'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('request-to-join')));
    await tester.tap(find.byKey(const ValueKey('request-to-join')));
    await tester.pumpAndSettle();

    expect(find.text('One quick step before you join'), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
