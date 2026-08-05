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
  bool _isSending = false;
  String? _errorMessage;

  List<TripConversation> get conversations => List.unmodifiable(_conversations);
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get errorMessage => _errorMessage;

  TripConversation? conversationById(String conversationId) {
    for (final conversation in _conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _conversations = await _repository.fetchConversations();
    } on Object {
      _errorMessage = 'Conversations could not be loaded. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _repository.watchMessages(conversationId);
  }

  Future<void> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw ArgumentError('Messages must contain 1 to 1000 characters.');
    }

    _isSending = true;
    _errorMessage = null;
    notifyListeners();
    try {
      await _repository.sendMessage(
        conversationId: conversationId,
        body: trimmed,
      );
      _conversations = await _repository.fetchConversations();
    } on Object {
      _errorMessage = 'Message could not be sent. Please try again.';
      rethrow;
    } finally {
      _isSending = false;
      notifyListeners();
    }
  }

  Future<void> markRead(String conversationId) async {
    try {
      await _repository.markRead(conversationId);
      _conversations = await _repository.fetchConversations();
      notifyListeners();
    } on Object {
      // Reading remains available even if the receipt cannot be persisted.
    }
  }
}
