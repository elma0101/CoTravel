import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../join_requests/domain/trip_join_request.dart';
import '../domain/trip_conversation.dart';

abstract interface class ChatRepository {
  Future<List<TripConversation>> fetchConversations();

  Stream<void> watchInbox();

  Future<ChatMessagePage> fetchMessages({
    required String conversationId,
    ChatMessageCursor? before,
    int limit = 40,
  });

  Stream<ChatRealtimeEvent> watchConversation(String conversationId);

  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
  });

  Future<void> markRead({required String conversationId, DateTime? through});
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
  Stream<void> watchInbox() {
    late RealtimeChannel channel;
    late StreamController<void> controller;

    controller = StreamController<void>(
      onListen: () {
        final inboxChannel = _client
            .channel('chat-inbox-${DateTime.now().microsecondsSinceEpoch}')
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_messages',
              callback: (_) => controller.add(null),
            );
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          inboxChannel.onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'conversation_members',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: (_) => controller.add(null),
          );
        }
        channel = inboxChannel.subscribe();
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<ChatMessagePage> fetchMessages({
    required String conversationId,
    ChatMessageCursor? before,
    int limit = 40,
  }) async {
    final rows = await _client.rpc<List<dynamic>>(
      'list_chat_messages',
      params: {
        'p_conversation_id': conversationId,
        'p_before_sent_at': before?.sentAt.toUtc().toIso8601String(),
        'p_before_id': before?.messageId,
        'p_limit': limit,
      },
    );
    final messages = rows
        .map((row) => _messageFromMap(row as Map<String, dynamic>))
        .toList()
        .reversed
        .toList(growable: false);
    return ChatMessagePage(messages: messages, hasMore: rows.length == limit);
  }

  @override
  Stream<ChatRealtimeEvent> watchConversation(String conversationId) {
    late RealtimeChannel channel;
    late StreamController<ChatRealtimeEvent> controller;

    controller = StreamController<ChatRealtimeEvent>(
      onListen: () {
        controller.add(
          const ChatRealtimeEvent.status(ChatRealtimeStatus.connecting),
        );
        channel = _client
            .channel(
              'chat-$conversationId-${DateTime.now().microsecondsSinceEpoch}',
            )
            .onPostgresChanges(
              event: PostgresChangeEvent.insert,
              schema: 'public',
              table: 'chat_messages',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'conversation_id',
                value: conversationId,
              ),
              callback: (payload) {
                if (payload.newRecord.isNotEmpty) {
                  controller.add(
                    ChatRealtimeEvent.message(
                      _messageFromMap(payload.newRecord),
                    ),
                  );
                }
              },
            )
            .subscribe((status, error) {
              if (controller.isClosed) {
                return;
              }
              controller.add(
                ChatRealtimeEvent.status(
                  status == RealtimeSubscribeStatus.subscribed
                      ? ChatRealtimeStatus.connected
                      : ChatRealtimeStatus.disconnected,
                ),
              );
            });
      },
      onCancel: () async {
        await _client.removeChannel(channel);
      },
    );
    return controller.stream;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    final response = await _client.rpc<dynamic>(
      'send_chat_message_v2',
      params: {
        'p_conversation_id': conversationId,
        'p_body': body,
        'p_client_id': clientId,
      },
    );
    final row = switch (response) {
      final List<dynamic> rows when rows.isNotEmpty =>
        rows.first as Map<String, dynamic>,
      final Map<String, dynamic> value => value,
      _ => throw StateError('The message server returned no message.'),
    };
    return _messageFromMap(row);
  }

  @override
  Future<void> markRead({
    required String conversationId,
    DateTime? through,
  }) async {
    await _client.rpc(
      'mark_conversation_read_through',
      params: {
        'p_conversation_id': conversationId,
        'p_read_through': through?.toUtc().toIso8601String(),
      },
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
          : DateTime.parse(row['last_message_at'] as String).toLocal(),
      unreadCount: (row['unread_count'] as num).toInt(),
    );
  }

  ChatMessage _messageFromMap(Map<String, dynamic> row) {
    return ChatMessage(
      id: (row['id'] ?? row['message_id']) as String,
      conversationId: row['conversation_id'] as String,
      senderId: row['sender_id'] as String?,
      senderName: row['sender_name'] as String?,
      body: row['body'] as String,
      type: row['message_type'] == 'system'
          ? ChatMessageType.system
          : ChatMessageType.member,
      sentAt: DateTime.parse(row['sent_at'] as String).toLocal(),
      clientId: row['client_id'] as String?,
    );
  }
}

class PreviewChatRepository implements ChatRepository {
  PreviewChatRepository({DateTime? now}) {
    _seed(now ?? DateTime.now());
  }

  final List<TripConversation> _conversations = [];
  final Map<String, List<ChatMessage>> _messages = {};
  final Map<String, StreamController<ChatRealtimeEvent>> _messageControllers =
      {};
  final StreamController<void> _inboxController =
      StreamController<void>.broadcast();
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
  Stream<void> watchInbox() => _inboxController.stream;

  @override
  Future<ChatMessagePage> fetchMessages({
    required String conversationId,
    ChatMessageCursor? before,
    int limit = 40,
  }) async {
    _requireConversation(conversationId);
    final allMessages = _messages[conversationId] ?? const [];
    var end = allMessages.length;
    if (before != null) {
      final cursorIndex = allMessages.indexWhere(
        (message) => message.id == before.messageId,
      );
      if (cursorIndex >= 0) {
        end = cursorIndex;
      } else {
        end = allMessages.indexWhere(
          (message) => !message.sentAt.isBefore(before.sentAt),
        );
        if (end < 0) {
          end = allMessages.length;
        }
      }
    }
    final start = (end - limit).clamp(0, end);
    return ChatMessagePage(
      messages: List.unmodifiable(allMessages.sublist(start, end)),
      hasMore: start > 0,
    );
  }

  @override
  Stream<ChatRealtimeEvent> watchConversation(String conversationId) async* {
    _requireConversation(conversationId);
    yield const ChatRealtimeEvent.status(ChatRealtimeStatus.connected);
    final controller = _messageControllers.putIfAbsent(
      conversationId,
      StreamController<ChatRealtimeEvent>.broadcast,
    );
    yield* controller.stream;
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
  }) async {
    _requireConversation(conversationId);
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.runes.length > 1000) {
      throw StateError('Messages must contain 1 to 1000 characters.');
    }
    final existing = _messages[conversationId]?.where(
      (message) => message.clientId == clientId,
    );
    if (existing != null && existing.isNotEmpty) {
      return existing.first;
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
      clientId: clientId,
    );
    final messages = _messages.putIfAbsent(conversationId, () => []);
    messages.add(message);
    _messageControllers[conversationId]?.add(
      ChatRealtimeEvent.message(message),
    );
    _updateConversation(
      conversationId,
      lastMessage: trimmed,
      lastMessageAt: sentAt,
      unreadCount: 0,
    );
    _inboxController.add(null);
    return message;
  }

  @override
  Future<void> markRead({
    required String conversationId,
    DateTime? through,
  }) async {
    _requireConversation(conversationId);
    _updateConversation(conversationId, unreadCount: 0);
    _inboxController.add(null);
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
      _inboxController.add(null);
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
    _inboxController.add(null);
  }

  void dispose() {
    for (final controller in _messageControllers.values) {
      controller.close();
    }
    _inboxController.close();
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
        clientId: 'preview-seeded-user-message',
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
