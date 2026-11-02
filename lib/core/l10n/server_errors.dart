import 'app_strings.dart';

/// The user-readable part of an error raised by the database or a controller,
/// translated. Null when the error is not meant for users.
String? readableServerError(Object error) {
  final text = error.toString();
  for (final prefix in ['Bad state: ', 'Invalid argument(s): ']) {
    if (text.startsWith(prefix)) {
      return tr(text.substring(prefix.length));
    }
  }
  final match = RegExp(
    r'^(?:Postgrest|Storage|Auth)(?:Api)?Exception\(message: (.*?), (?:code|statusCode):',
    dotAll: true,
  ).firstMatch(text);
  return match == null ? null : tr(match[1]!);
}
