import 'dart:async';

import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/features/profile/data/profile_repository.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Keeps the profile unfinished, as it is while someone is onboarding.
class _OnboardingProfileRepository extends PreviewProfileRepository {
  /// While set, profile requests wait for it, like a slow network.
  Completer<void>? pending;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    await pending?.future;
    return const UserProfile.incompletePreview();
  }
}

/// Signed in as `user-1` with onboarding still to do.
Future<AppAuthState> _onboardingState([
  _OnboardingProfileRepository? repository,
]) async {
  final authState = AppAuthState(
    supabaseClient: null,
    profileRepository: repository ?? _OnboardingProfileRepository(),
    previewAuthEnabled: true,
    authRedirectUrl: 'com.cotravel.app://login-callback',
  );
  await authState.synchronizeUser('user-1');
  return authState;
}

void main() {
  test('a refresh for the same user never passes through loading', () async {
    final authState = await _onboardingState();
    addTearDown(authState.dispose);
    final statuses = <AppSessionStatus>[];
    authState.addListener(() => statuses.add(authState.status));

    await authState.synchronizeUser('user-1');

    expect(statuses, isNot(contains(AppSessionStatus.loading)));
    expect(authState.status, AppSessionStatus.onboardingRequired);
  });

  test('a different user loads from scratch', () async {
    final authState = await _onboardingState();
    addTearDown(authState.dispose);
    final statuses = <AppSessionStatus>[];
    authState.addListener(() => statuses.add(authState.status));

    await authState.synchronizeUser('another-user');

    expect(statuses.first, AppSessionStatus.loading);
  });

  testWidgets('a session refresh keeps the sign-up step and its answers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    final repository = _OnboardingProfileRepository();
    final authState = await _onboardingState(repository);
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
      UncontrolledProviderScope(
        container: container,
        child: const CoTravelApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('setup-name')), 'Sam');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rabat'));
    await tester.pump();

    // What Supabase reports when the linked identity comes back.
    repository.pending = Completer<void>();
    final refresh = authState.synchronizeUser('user-1');
    await tester.pumpAndSettle();
    repository.pending!.complete();
    await refresh;
    await tester.pumpAndSettle();

    expect(find.text('Where are you based?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Culture'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('French'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('setup-continue')));
    await tester.pumpAndSettle();
    expect(find.text("You're in, Sam!"), findsOneWidget);
    expect(find.text('Rabat'), findsOneWidget);
  });
}
