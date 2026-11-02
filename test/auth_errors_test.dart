import 'package:cotravel_app/core/l10n/app_strings.dart';
import 'package:cotravel_app/core/l10n/auth_errors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  tearDown(() => appLanguageCode = 'en');

  test('a rate limit reads the same whatever seconds Supabase names', () {
    appLanguageCode = 'fr';
    const error = AuthException(
      'For security purposes, you can only request this after 37 seconds.',
      statusCode: '429',
      code: 'over_email_send_rate_limit',
    );

    expect(
      readableAuthError(error),
      'Trop de tentatives. Attendez une minute, puis réessayez.',
    );
  });

  test('a LinkedIn account linked elsewhere is explained', () {
    const error = AuthException(
      'Identity is already linked to another user',
      statusCode: '422',
      code: 'identity_already_exists',
    );

    expect(
      readableAuthError(error),
      'This LinkedIn account is already linked to another CoTravel account.',
    );
  });

  test('a lost connection asks to retry', () {
    expect(
      readableAuthError(AuthRetryableFetchException()),
      'Check your connection and try again.',
    );
  });

  test('an unknown code keeps the server message', () {
    const error = AuthException('Something new', code: 'brand_new_code');

    expect(readableAuthError(error), 'Something new');
  });

  test('other errors are left to the caller', () {
    expect(readableAuthError(StateError('nope')), isNull);
  });
}
