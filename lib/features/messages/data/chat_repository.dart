import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../join_requests/domain/trip_join_request.dart';
import '../domain/trip_conversation.dart';

abstract interface class ChatRepository {
  Future<List<TripConversation>> fetchConversations();

  Stream<List<ChatMessage>> watchMessages(String conversationId);

  Future<void> sendMessage({
    required String conversationId,
    required String body,
  });

  Future<void> markRead(String conversationId);
}

class SupabaseChatRepository implements ChatRepository {
  SupabaseChatRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<TripConversation>> fetchConversations() async {
    final rows = await _client.rpc<List<dynamic>>('my_trip_conversations');
    return rows
        .map((row) => _conversationFromMap(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _client
        .from('chat_messages')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .order('sent_at')
        .map((rows) => rows.map(_messageFromMap).toList());
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    await _client.rpc(
      'send_chat_message',
      params: {'p_conversation_id': conversationId, 'p_body': body},
    );
  }

  @override
  Future<void> markRead(String conversationId) async {
    await _client.rpc(
      'mark_conversation_read',
      params: {'p_conversation_id': conversationId},
    );
  }

  TripConversation _conversationFromMap(Map<String, dynamic> row) {
    return TripConversation(
      id: row['conversation_id'] as String,
      tripId: row['trip_id'] as String,
      tripTitle: row['trip_title'] as String,
      originCity: row['origin_city'] as String,
      destinationCity: row['destination_city'] as String,
      memberCount: (row['member_count'] as num).toInt(),
      lastMessage: row['last_message'] as String?,
      lastMessageAt: row['last_message_at'] == null
          ? null
          : DateTime.parse(row['last_message_at'] as String),
      unreadCount: (row['unread_count'] as num).toInt(),
    );
  }

  ChatMessage _messageFromMap(Map<String, dynamic> row) {
    return ChatMessage(
      id: row['id'] as String,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String?,
      senderName: row['sender_name'] as String?,
      body: row['body'] as String,
      type: row['message_type'] == 'system'
          ? ChatMessageType.system
          : ChatMessageType.member,
      sentAt: DateTime.parse(row['sent_at'] as String),
    );
  }
}

class PreviewChatRepository implements ChatRepository {
  PreviewChatRepository({DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  final List<TripConversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, StreamController<List<ChatMessage>>> _messageControllers =
      {};
  int _nextMessageId = 1;

  @override
  Future<List<TripConversation>> fetchConversations() async {
    return [..._conversations]..sort((left, right) {
      final leftDate = left.lastMessageAt ?? DateTime(1970);
      final rightDate = right.lastMessageAt ?? DateTime(1970);
      return rightDate.compareTo(leftDate);
    });
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) async* {
    _requireConversation(conversationId);
    yield List.unmodifiable(_messages[conversationId] ?? const []);
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      StreamController<List<ChatMessage>>.broadcast,
    );
    yield* controller.stream;
  }

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String body,
  }) async {
    _requireConversation(conversationId);
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.length > 1000) {
      throw StateError('Messages must contain 1 to 1000 characters.');
    }

    final sentAt = DateTime.now();
    final message = ChatMessage(
      id: 'preview-message-${_nextMessageId++}',
      conversationId: conversationId,
      senderId: 'preview-user',
      senderName: 'Preview traveler',
      body: trimmed,
      type: ChatMessageType.member,
      sentAt: sentAt,
    );
    final messages = _messages.putIfAbsent(conversationId, () => []);
    messages.add(message);
    _messageControllers[conversationId]?.add(List.unmodifiable(messages));
    _updateConversation(
      conversationId,
      lastMessage: trimmed,
      lastMessageAt: sentAt,
      unreadCount: 0,
    );
  }

  @override
  Future<void> markRead(String conversationId) async {
    _requireConversation(conversationId);
    _updateConversation(conversationId, unreadCount: 0);
  }

  Future<void> createForConfirmedRequest(TripJoinRequest request) async {
    if (_conversations.any((item) => item.tripId == request.tripId)) {
      final conversation = _conversations.firstWhere(
        (item) => item.tripId == request.tripId,
      );
      _updateConversation(
        conversation.id,
        memberCount: conversation.memberCount + 1,
      );
      return;
    }

    final conversationId = 'preview-conversation-${request.tripId}';
    final sentAt = DateTime.now();
    final systemBody =
        '${request.travelerName} confirmed their place. The trip chat is now open.';
    _conversations.add(
      TripConversation(
        id: conversationId,
        tripId: request.tripId,
        tripTitle: request.tripTitle,
        originCity: request.originCity,
        destinationCity: request.destinationCity,
        memberCount: 2,
        lastMessage: systemBody,
        lastMessageAt: sentAt,
        unreadCount: 0,
      ),
    );
    _messages[conversationId] = [
      ChatMessage(
        id: 'preview-system-${_nextMessageId++}',
        conversationId: conversationId,
        senderId: null,
        senderName: null,
        body: systemBody,
        type: ChatMessageType.system,
        sentAt: sentAt,
      ),
    ];
  }

  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
  }

  void _seed(DateTime value) {
    final now = DateTime(value.year, value.month, value.day, 12);
    const conversationId = 'preview-conversation-dades';
    _conversations.add(
      TripConversation(
        id: conversationId,
        tripId: 'dades-slow-road',
        tripTitle: 'Dades slow road',
        originCity: 'Marrakech',
        destinationCity: 'Boumalne Dades',
        memberCount: 3,
        lastMessage: 'I will share the guesthouse shortlist tonight.',
        lastMessageAt: now.subtract(const Duration(minutes: 18)),
        unreadCount: 1,
      ),
    );
    _messages[conversationId] = [
      ChatMessage(
        id: 'preview-system-dades',
        conversationId: conversationId,
        senderId: null,
        senderName: null,
        body: 'The group is confirmed. Keep planning details in this chat.',
        type: ChatMessageType.system,
        sentAt: now.subtract(const Duration(hours: 3)),
      ),
      ChatMessage(
        id: 'preview-host-dades',
        conversationId: conversationId,
        senderId: 'host-leila',
        senderName: 'Leila M.',
        body:
            'Welcome! Does an early departure from Marrakech work for both of you?',
        type: ChatMessageType.member,
        sentAt: now.subtract(const Duration(hours: 2, minutes: 45)),
      ),
      ChatMessage(
        id: 'preview-user-dades',
        conversationId: conversationId,
        senderId: 'preview-user',
        senderName: 'Preview traveler',
        body: 'Yes, any time after 7 works for me.',
        type: ChatMessageType.member,
        sentAt: now.subtract(const Duration(hours: 1)),
      ),
      ChatMessage(
        id: 'preview-host-shortlist',
        conversationId: conversationId,
        senderId: 'host-leila',
        senderName: 'Leila M.',
        body: 'I will share the guesthouse shortlist tonight.',
        type: ChatMessageType.member,
        sentAt: now.subtract(const Duration(minutes: 18)),
      ),
    ];
  }

  TripConversation _requireConversation(String conversationId) {
    return _conversations.firstWhere(
      (item) => item.id == conversationId,
      orElse: () => throw StateError('Conversation not found.'),
    );
  }

  void _updateConversation(
    String conversationId, {
    int? memberCount,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    final index = _conversations.indexWhere(
      (item) => item.id == conversationId,
    );
    final conversation = _conversations[index];
    _conversations[index] = conversation.copyWith(
      memberCount: memberCount,
      lastMessage: lastMessage,
      lastMessageAt: lastMessageAt,
      unreadCount: unreadCount,
    );
  }
}
