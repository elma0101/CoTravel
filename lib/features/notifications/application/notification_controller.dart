import '../../../core/l10n/app_strings.dart';
import '../../../core/state/dispose_safe_notifier.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/notification_repository.dart';
import '../domain/app_notification.dart';

class NotificationController extends ChangeNotifier with DisposeSafeNotifier {
  NotificationController({required NotificationRepository repository})
    : this._(repository);

  NotificationController._(this._repository);

  final NotificationRepository _repository;

  StreamSubscription<void>? _subscription;
  List<AppNotification> _notifications = const [];
  bool _isLoading = true;
  String? _errorMessage;

  List<AppNotification> get notifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  int get unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;

  Future<void> load() async {
    _subscription ??= _repository.watchNotifications().listen((_) {
      unawaited(load());
    });
    _errorMessage = null;
    try {
      _notifications = await _repository.fetchNotifications();
    } on Object {
      _errorMessage = tr(
        'Notifications could not be loaded. Please try again.',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> markRead(AppNotification notification) async {
    if (notification.isRead) {
      return;
    }
    final previous = _notifications;
    _notifications = _notifications
        .map((item) => item.id == notification.id ? item.markedRead() : item)
        .toList(growable: false);
    notifyListeners();
    try {
      await _repository.markRead(notification.id);
    } on Object {
      _notifications = previous;
      notifyListeners();
    }
  }

  // A tapped push can arrive before the inbox has loaded this notification.
  Future<void> markReadById(String notificationId) async {
    try {
      await _repository.markRead(notificationId);
    } on Object {
      return;
    }
    await load();
  }

  Future<void> markAllRead() async {
    final previous = _notifications;
    _notifications = _notifications
        .map((item) => item.markedRead())
        .toList(growable: false);
    notifyListeners();
    try {
      await _repository.markAllRead();
    } on Object {
      _notifications = previous;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
