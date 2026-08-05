import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/bootstrap/app_bootstrap.dart';
import 'app/config/app_config.dart';
import 'app/cotravel_app.dart';
import 'app/providers/app_providers.dart';
import 'core/widgets/app_async_views.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final config = AppConfig.fromEnvironment();

  try {
    final bootstrap = await AppBootstrap.initialize(config);

    runApp(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(config),
          supabaseClientProvider.overrideWithValue(bootstrap.supabaseClient),
        ],
        child: const CoTravelApp(),
      ),
    );
  } on Object catch (error) {
    runApp(BootstrapFailureApp(message: error.toString()));
  }
}
