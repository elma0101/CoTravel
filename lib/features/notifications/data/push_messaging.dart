import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract interface class PushMessaging {
  /// False when this build has no Firebase configuration.
  Future<bool> initialize();

  Future<bool> requestPermission();

  Future<String?> getToken();

  Future<void> deleteToken();

  Stream<String> get tokenRefreshes;

  /// The data of notifications tapped while the app was running.
  Stream<Map<String, String>> get openedMessages;

  /// The data of the notification that launched the app, if any.
  Future<Map<String, String>?> initialMessage();
}

// FCM's newer installation ID API has no documented send target in the HTTP v1
// API this project uses, so this stays on registration tokens for now.
// ignore_for_file: deprecated_member_use

class FirebasePushMessaging implements PushMessaging {
  FirebaseMessaging get _messaging => FirebaseMessaging.instance;

  @override
  Future<bool> initialize() async {
    try {
      await Firebase.initializeApp();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> requestPermission() async {
    final settings = await _messaging.requestPermission();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Future<void> deleteToken() => _messaging.deleteToken();

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<Map<String, String>> get openedMessages =>
      FirebaseMessaging.onMessageOpenedApp.map(_dataOf);

  @override
  Future<Map<String, String>?> initialMessage() async {
    final message = await _messaging.getInitialMessage();
    return message == null ? null : _dataOf(message);
  }

  Map<String, String> _dataOf(RemoteMessage message) {
    return message.data.map((key, value) => MapEntry(key, '$value'));
  }
}

/// Used in preview mode and on platforms without push set up.
class NoopPushMessaging implements PushMessaging {
  const NoopPushMessaging();

  @override
  Future<bool> initialize() async => false;

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<String?> getToken() async => null;

  @override
  Future<void> deleteToken() async {}

  @override
  Stream<String> get tokenRefreshes => const Stream.empty();

  @override
  Stream<Map<String, String>> get openedMessages => const Stream.empty();

  @override
  Future<Map<String, String>?> initialMessage() async => null;
}

abstract interface class PushTokenRepository {
  Future<void> register(String token);
}

class SupabasePushTokenRepository implements PushTokenRepository {
  SupabasePushTokenRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<void> register(String token) async {
    await _client.rpc('register_push_token', params: {'p_token': token});
  }
}

class NoopPushTokenRepository implements PushTokenRepository {
  const NoopPushTokenRepository();

  @override
  Future<void> register(String token) async {}
}
