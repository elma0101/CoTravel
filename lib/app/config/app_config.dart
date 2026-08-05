enum AppEnvironment { development, staging, production }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.supabaseUrl,
    required this.supabasePublishableKey,
    required this.requestPreviewAuth,
    required this.requireLinkedInVerification,
  });

  factory AppConfig.fromEnvironment() {
    const environmentValue = String.fromEnvironment(
      'APP_ENV',
      defaultValue: 'development',
    );

    return AppConfig(
      environment: switch (environmentValue) {
        'development' => AppEnvironment.development,
        'staging' => AppEnvironment.staging,
        'production' => AppEnvironment.production,
        _ => throw StateError('Unsupported APP_ENV: $environmentValue'),
      },
      supabaseUrl: const String.fromEnvironment('SUPABASE_URL'),
      supabasePublishableKey: const String.fromEnvironment(
        'SUPABASE_PUBLISHABLE_KEY',
      ),
      requestPreviewAuth: const bool.fromEnvironment(
        'ENABLE_PREVIEW_AUTH',
        defaultValue: true,
      ),
      requireLinkedInVerification: const bool.fromEnvironment(
        'REQUIRE_LINKEDIN_VERIFICATION',
      ),
    );
  }

  final AppEnvironment environment;
  final String supabaseUrl;
  final String supabasePublishableKey;
  final bool requestPreviewAuth;
  final bool requireLinkedInVerification;

  bool get hasSupabaseConfiguration =>
      supabaseUrl.trim().isNotEmpty && supabasePublishableKey.trim().isNotEmpty;

  bool get previewAuthEnabled =>
      environment == AppEnvironment.development && requestPreviewAuth;

  void validate() {
    final hasUrl = supabaseUrl.trim().isNotEmpty;
    final hasKey = supabasePublishableKey.trim().isNotEmpty;

    if (hasUrl != hasKey) {
      throw StateError(
        'SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY must be provided together.',
      );
    }

    if (hasUrl) {
      final uri = Uri.tryParse(supabaseUrl);
      if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
        throw StateError('SUPABASE_URL must be a valid absolute URL.');
      }
    }

    if (environment != AppEnvironment.development &&
        !hasSupabaseConfiguration) {
      throw StateError(
        'A Supabase configuration is required outside development.',
      );
    }
  }
}
