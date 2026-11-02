import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_strings.dart';

/// A translated message for an error from Supabase sign-in, or null when
/// [error] did not come from it. Supabase writes its messages in English and
/// some contain numbers, so the stable error code picks the text.
String? readableAuthError(Object error) {
  if (error is AuthRetryableFetchException) {
    return tr('Check your connection and try again.');
  }
  if (error is! AuthException) {
    return null;
  }
  return switch (error.code) {
    'over_email_send_rate_limit' ||
    'over_request_rate_limit' ||
    'over_sms_send_rate_limit' => tr(
      'Too many attempts. Wait a minute, then try again.',
    ),
    'email_address_invalid' ||
    'validation_failed' => tr('Enter a valid email address.'),
    'email_address_not_authorized' => tr(
      'Sign-in links cannot be sent to this address yet.',
    ),
    'otp_expired' || 'flow_state_expired' || 'flow_state_not_found' => tr(
      'This sign-in link has expired. Ask for a new one.',
    ),
    'email_not_confirmed' => tr('Confirm your email address first.'),
    'identity_already_exists' => tr(
      'This LinkedIn account is already linked to another CoTravel account.',
    ),
    'manual_linking_disabled' || 'provider_disabled' => tr(
      'LinkedIn verification is not available right now. Try again later.',
    ),
    'signup_disabled' => tr('New accounts are closed for now.'),
    'user_banned' => tr('This account has been suspended.'),
    'session_expired' ||
    'session_not_found' ||
    'refresh_token_not_found' ||
    'refresh_token_already_used' => tr(
      'Your session has ended. Sign in again.',
    ),
    'request_timeout' => tr('Check your connection and try again.'),
    _ => tr(error.message),
  };
}
