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

ProviderContainer _container(AppAuthState authState) {
  return ProviderContainer(
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
}

Future<ProviderContainer> _pump(
  WidgetTester tester,
  AppAuthState authState,
) async {
  final container = _container(authState);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: container, child: const CoTravelApp()),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('switching accounts', () {
    test('rebuilds everything that holds user data', () async {
      final auth = AppAuthState.preview(initiallyAuthenticated: true);
      final container = _container(auth);
      addTearDown(container.dispose);

      List<Object> readAll() => [
        container.read(tripCatalogProvider),
        container.read(safetyControllerProvider),
        container.read(logisticsControllerProvider),
        container.read(chatControllerProvider),
        container.read(notificationControllerProvider),
        container.read(joinRequestControllerProvider),
        container.read(betaFeedbackControllerProvider),
      ];
      final before = readAll();

      await auth.signOut();
      await container.pump();

      final after = readAll();
      for (var index = 0; index < before.length; index++) {
        expect(
          identical(before[index], after[index]),
          isFalse,
          reason: '$index',
        );
      }
    });

    test('keeps them when the same user refreshes their profile', () async {
      final auth = AppAuthState.preview(initiallyAuthenticated: true);
      final container = _container(auth);
      addTearDown(container.dispose);
      final before = container.read(tripCatalogProvider);

      await auth.updateProfile(
        draft: const ProfileDraft(
          displayName: 'New name',
          bio: 'A bio that is long enough.',
          homeCity: 'Fes',
          travelStyles: ['Culture'],
          languages: ['French'],
        ),
      );
      await container.pump();

      expect(identical(before, container.read(tripCatalogProvider)), isTrue);
    });
  });

  group('terms', () {
    test('an older acceptance does not count as current', () {
      const profile = UserProfile(
        id: 'user',
        displayName: 'Name',
        bio: null,
        homeCity: null,
        avatarUrl: null,
        travelStyles: [],
        languages: [],
        isLinkedInVerified: true,
        isOnboardingComplete: true,
        acceptedTermsVersion: 'old',
      );
      expect(profile.hasAcceptedCurrentTerms, isFalse);
    });

    testWidgets('can be read before signing in', (tester) async {
      final auth = AppAuthState.preview();
      await _pump(tester, auth);

      await tester.tap(find.text('Terms of use'));
      await tester.pumpAndSettle();

      expect(find.text('What CoTravel is'), findsOneWidget);
      expect(find.textContaining('pending legal review'), findsOneWidget);
    });

    test('the terms say CoTravel is not a travel agency', () {
      expect(
        termsOfUse.sections.first.body,
        contains('not a travel agency or tour operator'),
      );
    });
  });

  group('account deletion', () {
    Future<void> openDeletion(WidgetTester tester) async {
      await tester.tap(find.text('Profile'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('delete-account')),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const ValueKey('delete-account')));
      await tester.pumpAndSettle();
    }

    testWidgets('signs out and returns to welcome', (tester) async {
      final auth = AppAuthState.preview(initiallyAuthenticated: true);
      final container = await _pump(tester, auth);

      await openDeletion(tester);
      await tester.tap(find.byKey(const ValueKey('confirm-delete-account')));
      await tester.pumpAndSettle();

      expect(auth.status, AppSessionStatus.signedOut);
      expect(
        container
            .read(appRouterProvider)
            .routerDelegate
            .currentConfiguration
            .last
            .matchedLocation,
        AppRoutes.welcome,
      );
    });

    testWidgets('does nothing when dismissed', (tester) async {
      final auth = AppAuthState.preview(initiallyAuthenticated: true);
      await _pump(tester, auth);

      await openDeletion(tester);
      await tester.tap(find.text('Keep account'));
      await tester.pumpAndSettle();

      expect(auth.status, AppSessionStatus.authenticated);
    });
  });

  test('preview trust facts are available', () async {
    final facts = await PreviewProfileRepository().fetchTrustFacts(
      'host-amina',
    );
    expect(facts?.tripsHosted, 4);
  });
}
