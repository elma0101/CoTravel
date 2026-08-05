import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/chat_repository.dart';
import '../domain/trip_conversation.dart';

class ChatController extends ChangeNotifier {
  ChatController({required ChatRepository repository, required String userId})
    : this._(repository, userId);

  ChatController._(this._repository, this.userId);

  final ChatRepository _repository;
  final String userId;

  List<TripConversation> _conversations = const [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _refreshPending = false;
  String? _errorMessage;
  StreamSubscription<void>? _inboxSubscription;
  Timer? _refreshDebounce;
  bool _disposed = false;

  List<TripConversation> get conversations => List.unmodifiable(_conversations);
  bool get isLoading => _isLoading;
  bool get isRefreshing => _isRefreshing;
  String? get errorMessage => _errorMessage;
  int get totalUnreadCount => _conversations.fold(
    0,
    (total, conversation) => total + conversation.unreadCount,
  );

  TripConversation? conversationById(String conversationId) {
    for (final conversation in _conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> load() => _refresh(showLoading: _conversations.isEmpty);

  Future<void> refresh() => _refresh(showLoading: false);

  void markReadLocally(String conversationId) {
    final index = _conversations.indexWhere(
      (conversation) => conversation.id == conversationId,
    );
    if (index < 0 || _conversations[index].unreadCount == 0) {
      return;
    }
    final updated = [..._conversations];
    updated[index] = updated[index].copyWith(unreadCount: 0);
    _conversations = updated;
    _notifyIfMounted();
  }

  Future<void> _refresh({required bool showLoading}) async {
    if (_disposed) {
      return;
    }
    _ensureInboxSubscription();
    if (_isRefreshing) {
      _refreshPending = true;
      return;
    }
    _isRefreshing = true;
    if (showLoading) {
      _isLoading = true;
    }
    _errorMessage = null;
    _notifyIfMounted();
    try {
      _conversations = await _repository.fetchConversations();
    } on Object {
      if (_conversations.isEmpty) {
        _errorMessage = 'Conversations could not be loaded. Please try again.';
      }
    } finally {
      _isRefreshing = false;
      _isLoading = false;
      _notifyIfMounted();
      if (_refreshPending && !_disposed) {
        _refreshPending = false;
        unawaited(_refresh(showLoading: false));
      }
    }
  }

  void _ensureInboxSubscription() {
    _inboxSubscription ??= _repository.watchInbox().listen((_) {
      if (_disposed) {
        return;
      }
      _refreshDebounce?.cancel();
      _refreshDebounce = Timer(
        const Duration(milliseconds: 250),
        () => unawaited(refresh()),
      );
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshDebounce?.cancel();
    unawaited(_inboxSubscription?.cancel());
    super.dispose();
  }

  void _notifyIfMounted() {
    if (!_disposed) {
      notifyListeners();
    }
  }
}
