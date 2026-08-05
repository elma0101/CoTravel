import 'package:cotravel_app/features/join_requests/application/join_request_controller.dart';
import 'package:cotravel_app/features/join_requests/data/join_request_repository.dart';
import 'package:cotravel_app/features/join_requests/domain/trip_join_request.dart';
import 'package:cotravel_app/features/messages/application/chat_controller.dart';
import 'package:cotravel_app/features/messages/application/conversation_controller.dart';
import 'package:cotravel_app/features/messages/data/chat_repository.dart';
import 'package:cotravel_app/features/messages/domain/trip_conversation.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview chat streams and persists a sent message', () async {
    final repository = PreviewChatRepository(now: DateTime(2026, 8, 5));
    addTearDown(repository.dispose);
    final conversation = (await repository.fetchConversations()).single;

    final initialMessages = (await repository.fetchMessages(
      conversationId: conversation.id,
    )).messages;
    expect(initialMessages, hasLength(4));

    await repository.sendMessage(
      conversationId: conversation.id,
      body: 'I can compare the two guesthouses after dinner.',
      clientId: 'test-client-message-1',
    );

    final updatedMessages = (await repository.fetchMessages(
      conversationId: conversation.id,
    )).messages;
    expect(updatedMessages, hasLength(5));
    expect(updatedMessages.last.senderId, 'preview-user');
    expect(
      (await repository.fetchConversations()).single.lastMessage,
      'I can compare the two guesthouses after dinner.',
    );
  });

  test('dual approval automatically opens a trip conversation', () async {
    final now = DateTime(2026, 8, 5);
    final tripRepository = PreviewTripRepository(today: now);
    final tripCatalog = TripCatalogController(
      repository: tripRepository,
      userId: 'preview-user',
      hostProfile: const UserProfile.preview(),
    );
    final chatRepository = PreviewChatRepository(now: now);
    final chatController = ChatController(
      repository: chatRepository,
      userId: 'preview-user',
    );
    final requestRepository = PreviewJoinRequestRepository(
      tripRepository: tripRepository,
      now: now,
      onConfirmed: chatRepository.createForConfirmedRequest,
    );
    final requestController = JoinRequestController(
      repository: requestRepository,
      userId: 'preview-user',
      profile: const UserProfile.preview(),
      tripCatalog: tripCatalog,
      refreshChats: chatController.load,
    );
    addTearDown(() {
      requestController.dispose();
      chatController.dispose();
      chatRepository.dispose();
      tripCatalog.dispose();
    });

    await tripCatalog.load();
    await chatController.load();
    await requestController.load();
    expect(chatController.conversations, hasLength(1));

    final approval = requestController.travelerRequests.firstWhere(
      (request) => request.status == JoinRequestStatus.pendingTraveler,
    );
    await requestController.confirmAsTraveler(approval, confirm: true);

    expect(chatController.conversations, hasLength(2));
    final created = chatController.conversations.firstWhere(
      (conversation) => conversation.tripId == approval.tripId,
    );
    expect(created.memberCount, 2);
    final messages = (await chatRepository.fetchMessages(
      conversationId: created.id,
    )).messages;
    expect(messages.single.type.name, 'system');
  });

  test('message history paginates without overlaps', () async {
    final repository = PreviewChatRepository(now: DateTime(2026, 8, 5));
    addTearDown(repository.dispose);
    final conversation = (await repository.fetchConversations()).single;

    for (var index = 0; index < 45; index++) {
      await repository.sendMessage(
        conversationId: conversation.id,
        body: 'Planning update $index',
        clientId: 'pagination-client-$index',
      );
    }

    final latest = await repository.fetchMessages(
      conversationId: conversation.id,
    );
    expect(latest.messages, hasLength(40));
    expect(latest.hasMore, isTrue);

    final oldestLoaded = latest.messages.first;
    final earlier = await repository.fetchMessages(
      conversationId: conversation.id,
      before: ChatMessageCursor(
        sentAt: oldestLoaded.sentAt,
        messageId: oldestLoaded.id,
      ),
    );
    expect(earlier.messages, hasLength(9));
    expect(earlier.hasMore, isFalse);
    expect(
      earlier.messages
          .map((message) => message.id)
          .toSet()
          .intersection(latest.messages.map((message) => message.id).toSet()),
      isEmpty,
    );
  });

  test(
    'failed optimistic messages retry without creating duplicates',
    () async {
      final preview = PreviewChatRepository(now: DateTime(2026, 8, 5));
      final repository = _FailFirstSendChatRepository(preview);
      final conversation = (await repository.fetchConversations()).single;
      final controller = ConversationController(
        repository: repository,
        conversationId: conversation.id,
        userId: 'preview-user',
        userName: 'Preview traveler',
        onInboxChanged: () {},
        onConversationRead: () {},
      );
      addTearDown(() {
        controller.dispose();
        preview.dispose();
      });

      await controller.start();
      await controller.send('Retry this exact message.');

      final failed = controller.messages.last;
      expect(failed.deliveryStatus, ChatDeliveryStatus.failed);
      expect(controller.messages, hasLength(5));

      await controller.retry(failed);

      expect(controller.messages, hasLength(5));
      expect(controller.messages.last.deliveryStatus, ChatDeliveryStatus.sent);
      expect(controller.messages.last.body, 'Retry this exact message.');
    },
  );
}

class _FailFirstSendChatRepository implements ChatRepository {
  _FailFirstSendChatRepository(this.delegate);

  final ChatRepository delegate;
  bool _shouldFail = true;

  @override
  Future<List<TripConversation>> fetchConversations() {
    return delegate.fetchConversations();
  }

  @override
  Future<ChatMessagePage> fetchMessages({
    required String conversationId,
    ChatMessageCursor? before,
    int limit = 40,
  }) {
    return delegate.fetchMessages(
      conversationId: conversationId,
      before: before,
      limit: limit,
    );
  }

  @override
  Future<void> markRead({required String conversationId, DateTime? through}) {
    return delegate.markRead(conversationId: conversationId, through: through);
  }

  @override
  Future<ChatMessage> sendMessage({
    required String conversationId,
    required String body,
    required String clientId,
  }) {
    if (_shouldFail) {
      _shouldFail = false;
      throw StateError('Simulated network failure');
    }
    return delegate.sendMessage(
      conversationId: conversationId,
      body: body,
      clientId: clientId,
    );
  }

  @override
  Stream<ChatRealtimeEvent> watchConversation(String conversationId) {
    return delegate.watchConversation(conversationId);
  }

  @override
  Stream<void> watchInbox() => delegate.watchInbox();
}
