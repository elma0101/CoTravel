import 'package:cotravel_app/core/errors/error_reporter.dart';
import 'package:cotravel_app/core/l10n/app_strings.dart';
import 'package:cotravel_app/core/l10n/server_errors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('error reporter', () {
    late List<String> sent;
    late ErrorReporter reporter;

    setUp(() {
      sent = [];
      reporter = ErrorReporter(({
        required kind,
        required stack,
        required appVersion,
        required platform,
      }) async {
        sent.add('$kind|$stack');
      });
    });

    test('sends the type and stack but never the message', () async {
      await reporter.report(
        StateError('my passport number'),
        StackTrace.fromString('frame'),
      );

      expect(sent, ['StateError|frame']);
    });

    test('sends a repeated crash once', () async {
      final stack = StackTrace.fromString('frame');
      await reporter.report(StateError('a'), stack);
      await reporter.report(StateError('b'), stack);

      expect(sent, hasLength(1));
    });

    test('stops after the session limit', () async {
      for (var index = 0; index < 30; index++) {
        await reporter.report(StateError('a'), StackTrace.fromString('$index'));
      }

      expect(sent, hasLength(ErrorReporter.maxReportsPerSession));
    });

    test('cuts long stacks and survives a failed send', () async {
      final failing = ErrorReporter(({
        required kind,
        required stack,
        required appVersion,
        required platform,
      }) async {
        expect(stack.length, ErrorReporter.maxStackLength);
        throw StateError('offline');
      });

      await failing.report(StateError('a'), StackTrace.fromString('x' * 9000));
    });
  });

  group('server errors', () {
    tearDown(() => appLanguageCode = 'en');

    test('read the message out of each error shape', () {
      expect(
        readableServerError(StateError('This trip has no open seats')),
        'This trip has no open seats',
      );
      expect(readableServerError(Exception('nothing readable')), isNull);
    });

    test('are translated', () {
      appLanguageCode = 'fr';
      expect(
        readableServerError(StateError('This trip has no open seats')),
        'Ce voyage n’a plus de place libre',
      );
    });
  });
}
