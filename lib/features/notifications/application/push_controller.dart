import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/auth/app_auth_state.dart';
import '../data/push_messaging.dart';

class PushOpen {
  const PushOpen({required this.data});

  final Map<String, String> data;

  String? get notificationId => data['notification_id'];
  String? get kind => data['kind'];
  String? get tripId => data['trip_id'];
}

class PushController {
  PushController({
    required AppAuthState authState,
    required PushMessaging messaging,
    required PushTokenRepository tokens,
  }) : this._(authState, messaging, tokens);

  PushController._(this._authState, this._messaging, this._tokens);

  final AppAuthState _authState;
  final PushMessaging _messaging;
  final PushTokenRepository _tokens;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  AppSessionStatus? _lastStatus;
  bool _isAvailable = false;
  void Function(PushOpen open)? _onOpen;
  PushOpen? _pendingOpen;

  // Token work runs one step at a time, so a sign-out's delete cannot overtake or
  // interleave with the next account's registration.
  Future<void> _tokenWork = Future.value();

  void attach(void Function(PushOpen open) onOpen) {
    _onOpen = onOpen;
    _flushOpen();
  }

  Future<void> start() async {
    _isAvailable = await _messaging.initialize();
    if (!_isAvailable) {
      return;
    }

    _subscriptions
      ..add(
        _messaging.tokenRefreshes.listen((token) {
          if (_authState.isAuthenticated) {
            _enqueue(() => _tokens.register(token));
          }
        }),
      )
      ..add(_messaging.openedMessages.listen(_handleOpen));
    _authState.addListener(_onAuthChanged);
    _onAuthChanged();

    try {
      final initial = await _messaging.initialMessage();
      if (initial != null) {
        _handleOpen(initial);
      }
    } on Object catch (error) {
      debugPrint('Push launch message unavailable: $error');
    }
  }

  void _onAuthChanged() {
    _flushOpen();

    final status = _authState.status;
    if (status == _lastStatus) {
      return;
    }
    _lastStatus = status;

    if (status == AppSessionStatus.authenticated) {
      _enqueue(_registerDevice);
    } else if (status == AppSessionStatus.signedOut) {
      // Revoking the token here also covers an expired session, where the server
      // can no longer be called as that user. FCM rejects it from then on, and the
      // sender removes its row. Starting signed out retries an offline sign-out.
      _enqueue(_messaging.deleteToken);
    }
  }

  Future<void> _registerDevice() async {
    if (!await _messaging.requestPermission()) {
      return;
    }
    final token = await _messaging.getToken();
    if (token != null && _authState.isAuthenticated) {
      await _tokens.register(token);
    }
  }

  void _enqueue(Future<void> Function() work) {
    _tokenWork = _tokenWork.then((_) => work()).catchError((Object error) {
      // Push is an extra channel. The inbox still works if this fails.
      debugPrint('Push token update failed: $error');
    });
  }

  void _handleOpen(Map<String, String> data) {
    _pendingOpen = PushOpen(data: data);
    _flushOpen();
  }

  void _flushOpen() {
    final open = _pendingOpen;
    final onOpen = _onOpen;
    if (open != null && onOpen != null && _authState.isAuthenticated) {
      _pendingOpen = null;
      onOpen(open);
    }
  }

  void dispose() {
    _authState.removeListener(_onAuthChanged);
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
  }
}
