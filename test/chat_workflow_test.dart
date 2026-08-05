import 'package:cotravel_app/features/join_requests/application/join_request_controller.dart';
import 'package:cotravel_app/features/join_requests/data/join_request_repository.dart';
import 'package:cotravel_app/features/join_requests/domain/trip_join_request.dart';
import 'package:cotravel_app/features/messages/application/chat_controller.dart';
import 'package:cotravel_app/features/messages/data/chat_repository.dart';
import 'package:cotravel_app/features/profile/domain/user_profile.dart';
import 'package:cotravel_app/features/trips/application/trip_catalog_controller.dart';
import 'package:cotravel_app/features/trips/data/trip_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preview chat streams and persists a sent message', () async {
    final repository = PreviewChatRepository(now: DateTime(2026, 8, 5));
    addTearDown(repository.dispose);
    final conversation = (await repository.fetchConversations()).single;

    final initialMessages = await repository
        .watchMessages(conversation.id)
        .first;
    expect(initialMessages, hasLength(4));

    await repository.sendMessage(
      conversationId: conversation.id,
      body: 'I can compare the two guesthouses after dinner.',
    );

    final updatedMessages = await repository
        .watchMessages(conversation.id)
        .first;
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
    final messages = await chatController.watchMessages(created.id).first;
    expect(messages.single.type.name, 'system');
  });
}
