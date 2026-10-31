// Renders preview-mode screens to docs/baseline-screens at a phone size, for
// comparison with the mockups. Lives outside test/ so it does not run in CI.
//
//   flutter test tool/capture_screens.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cotravel_app/app/auth/app_auth_state.dart';
import 'package:cotravel_app/app/config/app_config.dart';
import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/app/router/app_router.dart';
import 'package:cotravel_app/app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _screens = {
  '01-explore': AppRoutes.explore,
  '03-create-trip': AppRoutes.createTrip,
  '04-my-trips': AppRoutes.trips,
  '05-messages': AppRoutes.messages,
  '06-profile': AppRoutes.profile,
  '07-safety': AppRoutes.safety,
};

final _tripDetails = AppRoutes.tripDetails('atlas-weekend');
final _joinRequests = AppRoutes.tripRequests('preview-rif-loop');
final _logistics = AppRoutes.tripLogistics('dades-slow-road');

Future<void> _loadFont(String family, List<String> files) async {
  final fonts =
      '${Platform.environment['FLUTTER_ROOT']}'
      '/bin/cache/artifacts/material_fonts';
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File('$fonts/$file').readAsBytesSync();
    loader.addFont(Future.value(ByteData.sublistView(bytes)));
  }
  await loader.load();
}

// CoTravelApp with a real font: the test engine draws text in blocks otherwise.
class _CaptureApp extends ConsumerWidget {
  const _CaptureApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = AppTheme.light;
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: theme.copyWith(
        textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: theme.elevatedButtonTheme.style?.copyWith(
            textStyle: const WidgetStatePropertyAll(
              TextStyle(
                fontFamily: 'Roboto',
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        navigationBarTheme: theme.navigationBarTheme.copyWith(
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => theme.navigationBarTheme.labelTextStyle
                ?.resolve(states)
                ?.copyWith(fontFamily: 'Roboto'),
          ),
        ),
      ),
      routerConfig: ref.watch(appRouterProvider),
    );
  }
}

void main() {
  testWidgets('capture baseline screens', (tester) async {
    await tester.runAsync(() async {
      await _loadFont('Roboto', [
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]);
      await _loadFont('MaterialIcons', ['MaterialIcons-Regular.otf']);
    });
    tester.view
      ..physicalSize = const Size(1170, 2532)
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    Directory('docs/baseline-screens').createSync(recursive: true);

    final authState = AppAuthState.preview(initiallyAuthenticated: true);
    const boundaryKey = ValueKey('capture');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ProviderScope(
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
          child: const _CaptureApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final router = tester
        .widget<MaterialApp>(find.byType(MaterialApp))
        .routerConfig!;

    Future<void> capture(String name, String location) async {
      (router as dynamic).go(location);
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        for (final element in find.byType(Image).evaluate()) {
          await precacheImage((element.widget as Image).image, element);
        }
      });
      await tester.pumpAndSettle();
      final boundary =
          tester.renderObject(find.byKey(boundaryKey)) as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        File(
          'docs/baseline-screens/$name.png',
        ).writeAsBytesSync(data!.buffer.asUint8List());
      });
    }

    for (final MapEntry(key: name, value: location) in _screens.entries) {
      await capture(name, location);
    }
    await capture('02-trip-details', _tripDetails);
    await capture('08-join-requests', _joinRequests);
    await capture('09-logistics', _logistics);
  });
}
