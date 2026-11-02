import 'dart:io';

import 'package:cotravel_app/core/l10n/app_strings.dart';
import 'package:cotravel_app/core/l10n/french_strings.dart';
import 'package:cotravel_app/features/join_requests/domain/trip_join_request.dart';
import 'package:cotravel_app/features/legal/domain/legal_documents.dart';
import 'package:cotravel_app/features/safety/domain/safety_models.dart';
import 'package:cotravel_app/features/trips/presentation/trip_formatters.dart';
import 'package:flutter_test/flutter_test.dart';

final _trCall = RegExp(r"\btr\(\s*'((?:[^'\\]|\\.)*)'");
final _pluralCall = RegExp(
  r"\btrPlural\(\s*[^,]+,\s*'((?:[^'\\]|\\.)*)',\s*'((?:[^'\\]|\\.)*)'",
);
final _placeholder = RegExp(r'\{(\w+)\}');

String _unescape(String source) =>
    source.replaceAll(r'\n', '\n').replaceAll(r"\'", "'");

Set<String> _placeholders(String text) =>
    _placeholder.allMatches(text).map((match) => match[1]!).toSet();

Set<String> _sourceStrings() {
  final strings = <String>{};
  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final source = entity.readAsStringSync();
    for (final match in _trCall.allMatches(source)) {
      strings.add(_unescape(match[1]!));
    }
    for (final match in _pluralCall.allMatches(source)) {
      strings
        ..add(_unescape(match[1]!))
        ..add(_unescape(match[2]!));
    }
  }
  return strings;
}

void main() {
  tearDown(() => appLanguageCode = 'en');

  test('every translated string in the code has French', () {
    final missing = _sourceStrings().difference(frenchStrings.keys.toSet());
    expect(missing, isEmpty);
  });

  test('strings passed to tr at runtime have French', () {
    final dynamicStrings = <String>[
      ...['Culture', 'Food', 'Nature', 'Road trips', 'Budget', 'Remote work'],
      ...SafetyReportReason.values.map((value) => value.label),
      ...SafetyReportStatus.values.map((value) => value.label),
      termsOfUse.title,
      privacyPolicy.title,
      for (final document in [termsOfUse, privacyPolicy])
        for (final section in document.sections) ...[
          section.heading,
          section.body,
        ],
    ];
    expect(
      dynamicStrings.where((text) => !frenchStrings.containsKey(text)),
      isEmpty,
    );
  });

  test('French keeps the same placeholders as English', () {
    frenchStrings.forEach((english, french) {
      if (english.startsWith('Your {n} confirmed traveler ')) return;
      expect(_placeholders(french), _placeholders(english), reason: english);
    });
  });

  test('tr falls back to English and fills in values', () {
    expect(
      tr('Waiting for {hostName}', {'hostName': 'Amina'}),
      'Waiting for Amina',
    );
    appLanguageCode = 'fr';
    expect(
      tr('Waiting for {hostName}', {'hostName': 'Amina'}),
      'En attente de Amina',
    );
    expect(tr('Not in the catalog'), 'Not in the catalog');
  });

  test('French treats zero as singular', () {
    expect(trPlural(0, '{n} stop', '{n} stops'), '0 stops');
    appLanguageCode = 'fr';
    expect(trPlural(0, '{n} stop', '{n} stops'), '0 étape');
    expect(trPlural(2, '{n} stop', '{n} stops'), '2 étapes');
  });

  test('dates follow the language', () {
    final date = DateTime(2026, 2, 7);
    expect(formatTripDate(date), '7 Feb');
    expect(JoinRequestStatus.confirmed.label, 'Spot confirmed');
    appLanguageCode = 'fr';
    expect(formatTripDate(date), '7 févr.');
    expect(formatMonthYear(date), 'février 2026');
    expect(JoinRequestStatus.confirmed.label, 'Place confirmée');
  });
}
