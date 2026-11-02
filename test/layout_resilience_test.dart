import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/cotravel_app.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

final _screens = <String, String>{
  'Explore': AppRoutes.explore,
  'My trips': AppRoutes.trips,
  'Messages': AppRoutes.messages,
  'Profile': AppRoutes.profile,
  'Notifications': AppRoutes.notifications,
  'Create trip': AppRoutes.createTrip,
  'Trip details': AppRoutes.tripDetails('dades-slow-road'),
  'Open trip details': AppRoutes.tripDetails('northern-colors'),
  'Requests': AppRoutes.tripRequests('preview-rif-loop'),
  'Logistics': AppRoutes.tripLogistics('dades-slow-road'),
  'Edit trip': AppRoutes.editTrip('preview-rif-loop'),
  'Edit profile': AppRoutes.editProfile,
  'Safety center': AppRoutes.safety,
  'Beta feedback': AppRoutes.betaFeedback,
  'Terms': AppRoutes.terms,
  'Privacy': AppRoutes.privacy,
};

Future<void> _open(WidgetTester tester, String location) async {
  final authState = AppAuthState.preview(initiallyAuthenticated: true);
  addTearDown(authState.dispose);
  await _pump(tester, authState);
  GoRouter.of(tester.element(find.byType(Scaffold).first)).go(location);
  await tester.pumpAndSettle();
}

Future<void> _pump(WidgetTester tester, AppAuthState authState) async {
  await tester.pumpWidget(
    ProviderScope(
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
      child: const CoTravelApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final language in ['en', 'fr']) {
    testWidgets('$language: Welcome fits a small phone with large text', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = [Locale(language)];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      addTearDown(() => appLanguageCode = 'en');
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final authState = AppAuthState.preview();
      addTearDown(authState.dispose);

      await _pump(tester, authState);

      expect(tester.takeException(), isNull);
    });

    for (final entry in _screens.entries) {
      testWidgets(
        '$language: ${entry.key} fits a small phone with large text',
        (tester) async {
          tester.platformDispatcher.localesTestValue = [Locale(language)];
          addTearDown(tester.platformDispatcher.clearLocalesTestValue);
          addTearDown(() => appLanguageCode = 'en');
          tester.view.physicalSize = const Size(320, 640);
          tester.view.devicePixelRatio = 1;
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(tester.view.reset);
          addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

          await _open(tester, entry.value);

          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final entry in _screens.entries) {
    testWidgets('${entry.key} meets the Android accessibility guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _open(tester, entry.value);

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  }
}
