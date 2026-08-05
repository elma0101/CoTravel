enum ChatMessageType { member, system }

enum ChatDeliveryStatus { sending, sent, failed }

enum ChatRealtimeStatus { connecting, connected, disconnected }

class TripConversation {
  const TripConversation({
    required this.id,
    required this.tripId,
    required this.tripTitle,
    required this.originCity,
    required this.destinationCity,
    required this.memberCount,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  final String id;
  final String tripId;
  final String tripTitle;
  final String originCity;
  final String destinationCity;
  final int memberCount;
  final String? lastMessage;
  final DateTime? lastMessageAt;
  final int unreadCount;

  String get routeLabel => '$originCity to $destinationCity';

  TripConversation copyWith({
    int? memberCount,
    String? lastMessage,
    DateTime? lastMessageAt,
    int? unreadCount,
  }) {
    return TripConversation(
      id: id,
      tripId: tripId,
      tripTitle: tripTitle,
      originCity: originCity,
      destinationCity: destinationCity,
      memberCount: memberCount ?? this.memberCount,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageAt: lastMessageAt ?? this.lastMessageAt,
      unreadCount: unreadCount ?? this.unreadCount,
    );
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.type,
    required this.sentAt,
    this.clientId,
    this.deliveryStatus = ChatDeliveryStatus.sent,
  });

  final String id;
  final String conversationId;
  final String? senderId;
  final String? senderName;
  final String body;
  final ChatMessageType type;
  final DateTime sentAt;
  final String? clientId;
  final ChatDeliveryStatus deliveryStatus;

  bool isMine(String userId) => senderId == userId;

  String get stableId => clientId ?? id;

  ChatMessage copyWith({
    String? id,
    DateTime? sentAt,
    ChatDeliveryStatus? deliveryStatus,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      senderName: senderName,
      body: body,
      type: type,
      sentAt: sentAt ?? this.sentAt,
      clientId: clientId,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }
}

class ChatMessageCursor {
  const ChatMessageCursor({required this.sentAt, required this.messageId});

  final DateTime sentAt;
  final String messageId;
}

class ChatMessagePage {
  const ChatMessagePage({required this.messages, required this.hasMore});

  final List<ChatMessage> messages;
  final bool hasMore;
}

class ChatRealtimeEvent {
  const ChatRealtimeEvent.status(this.status) : message = null;

  const ChatRealtimeEvent.message(this.message)
    : status = ChatRealtimeStatus.connected;

  final ChatRealtimeStatus status;
  final ChatMessage? message;
}
