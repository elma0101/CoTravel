import 'package:cotravel_app/app/config/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig', () {
    test('allows backend-free development preview', () {
      const config = AppConfig(
        environment: AppEnvironment.development,
        supabaseUrl: '',
        supabasePublishableKey: '',
        requestPreviewAuth: true,
        requireLinkedInVerification: false,
      );

      expect(config.validate, returnsNormally);
      expect(config.previewAuthEnabled, isTrue);
      expect(config.hasSupabaseConfiguration, isFalse);
    });

    test('never enables preview authentication outside development', () {
      const config = AppConfig(
        environment: AppEnvironment.staging,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: 'publishable-key',
        requestPreviewAuth: true,
        requireLinkedInVerification: true,
      );

      expect(config.previewAuthEnabled, isFalse);
    });

    test('rejects partial backend configuration', () {
      const config = AppConfig(
        environment: AppEnvironment.development,
        supabaseUrl: 'https://example.supabase.co',
        supabasePublishableKey: '',
        requestPreviewAuth: true,
        requireLinkedInVerification: false,
      );

      expect(config.validate, throwsStateError);
    });

    test('requires backend configuration in staging', () {
      const config = AppConfig(
        environment: AppEnvironment.staging,
        supabaseUrl: '',
        supabasePublishableKey: '',
        requestPreviewAuth: false,
        requireLinkedInVerification: true,
      );

      expect(config.validate, throwsStateError);
    });
  });
}
