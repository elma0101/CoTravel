import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';

class AppBootstrap {
  const AppBootstrap._({required this.supabaseClient});

  final SupabaseClient? supabaseClient;

  static Future<AppBootstrap> initialize(AppConfig config) async {
    config.validate();

    if (!config.hasSupabaseConfiguration) {
      return const AppBootstrap._(supabaseClient: null);
    }

    await Supabase.initialize(
      url: config.supabaseUrl,
      publishableKey: config.supabasePublishableKey,
    );

    return AppBootstrap._(supabaseClient: Supabase.instance.client);
  }
}
