import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef ErrorSender =
    Future<void> Function({
      required String kind,
      required String stack,
      required String appVersion,
      required String platform,
    });

/// Sends crashes to a service-only table. Only the error type and code stack
/// leave the device, never the error message, which can quote what a user
/// typed. Reports carry no account.
class ErrorReporter {
  ErrorReporter(this._send);

  factory ErrorReporter.supabase(SupabaseClient client) {
    return ErrorReporter(({
      required kind,
      required stack,
      required appVersion,
      required platform,
    }) async {
      // The function is closed to signed-out callers.
      if (client.auth.currentUser == null) {
        return;
      }
      await client.rpc(
        'report_client_error',
        params: {
          'p_kind': kind,
          'p_stack': stack,
          'p_app_version': appVersion,
          'p_platform': platform,
        },
      );
    });
  }

  static const maxReportsPerSession = 20;
  static const maxStackLength = 4000;
  static const _appVersion = String.fromEnvironment(
    'FLUTTER_BUILD_NAME',
    defaultValue: 'unknown',
  );

  final ErrorSender _send;
  final Set<String> _seen = {};

  void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack);
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      // Leaves the error to the default handler, which logs it.
      return false;
    };
  }

  Future<void> report(Object error, StackTrace? stack) async {
    final kind = error.runtimeType.toString();
    var trace = stack?.toString() ?? '';
    if (trace.length > maxStackLength) {
      trace = trace.substring(0, maxStackLength);
    }
    // A broken frame can throw on every rebuild, so send each crash once.
    if (_seen.length >= maxReportsPerSession || !_seen.add('$kind\n$trace')) {
      return;
    }
    try {
      await _send(
        kind: kind,
        stack: trace,
        appVersion: _appVersion,
        platform: defaultTargetPlatform.name,
      );
    } on Object catch (sendError) {
      // Never report a failed report, or an outage would loop.
      debugPrint('Error report failed: ${sendError.runtimeType}');
    }
  }
}
