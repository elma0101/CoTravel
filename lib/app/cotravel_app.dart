import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/l10n/app_strings.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

class CoTravelApp extends ConsumerWidget {
  const CoTravelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'CoTravel',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: ref.watch(appRouterProvider),
      supportedLocales: supportedAppLocales,
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) {
        appLanguageCode = Localizations.localeOf(context).languageCode;
        // Screens read the language through tr(), so a change must rebuild them.
        return KeyedSubtree(
          key: ValueKey(appLanguageCode),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
