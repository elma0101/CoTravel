import 'dart:ui';

import 'french_strings.dart';

const supportedAppLocales = [Locale('en'), Locale('fr')];

/// The English text in the code is the key. Controllers and domain labels have
/// no BuildContext, so the language is held here and set once by the app root.
String appLanguageCode = 'en';

String tr(String source, [Map<String, Object?> args = const {}]) {
  var text = appLanguageCode == 'fr'
      ? (frenchStrings[source] ?? source)
      : source;
  for (final entry in args.entries) {
    text = text.replaceAll('{${entry.key}}', '${entry.value}');
  }
  return text;
}

/// French treats zero as singular, English does not.
String trPlural(
  int count,
  String one,
  String other, [
  Map<String, Object?> args = const {},
]) {
  final singular = appLanguageCode == 'fr' ? count <= 1 : count == 1;
  return tr(singular ? one : other, {...args, 'n': count});
}
