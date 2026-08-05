enum ChatMessageType { member, system }

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
  });

  final String id;
  final String conversationId;
  final String? senderId;
  final String? senderName;
  final String body;
  final ChatMessageType type;
  final DateTime sentAt;

  bool isMine(String userId) => senderId == userId;
}
