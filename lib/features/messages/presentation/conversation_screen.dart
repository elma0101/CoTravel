import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/analytics/product_analytics.dart';
import '../application/chat_controller.dart';
import '../application/conversation_controller.dart';
import '../domain/trip_conversation.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  late ChatController _chatController;
  late ConversationController _conversationController;
  int _previousMessageCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatController = ref.read(chatControllerProvider);
    final profile = ref.read(appAuthStateProvider).profile;
    _conversationController = ConversationController(
      repository: ref.read(chatRepositoryProvider),
      conversationId: widget.conversationId,
      userId: profile?.id ?? _chatController.userId,
      userName: profile?.displayName ?? 'CoTravel member',
      onInboxChanged: () => unawaited(_chatController.refresh()),
      onConversationRead: () =>
          _chatController.markReadLocally(widget.conversationId),
    );
    _conversationController.addListener(_handleConversationChanged);
    _scrollController.addListener(_handleScroll);
    unawaited(_conversationController.start());

    final conversation = _chatController.conversationById(
      widget.conversationId,
    );
    unawaited(
      ref
          .read(productAnalyticsProvider)
          .track(ProductEvent.conversationOpened, tripId: conversation?.tripId),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _conversationController.setActive(state == AppLifecycleState.resumed);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) {
      return;
    }
    if (_scrollController.position.extentAfter < 240) {
      unawaited(_conversationController.loadOlder());
    }
  }

  void _handleConversationChanged() {
    final nextCount = _conversationController.messages.length;
    final shouldFollowLatest =
        !_scrollController.hasClients ||
        _scrollController.position.pixels < 120;
    if (nextCount > _previousMessageCount && shouldFollowLatest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          );
        }
      });
    }
    _previousMessageCount = nextCount;
  }

  void _send() {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }
    _messageController.clear();
    setState(() {});
    unawaited(_conversationController.send(body));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _conversationController.removeListener(_handleConversationChanged);
    _conversationController.dispose();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    final safety = ref.watch(safetyControllerProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([chat, safety, _conversationController]),
      builder: (context, child) {
        final conversation = chat.conversationById(widget.conversationId);
        return Scaffold(
          backgroundColor: AppColors.canvas,
          appBar: AppBar(
            titleSpacing: 0,
            title: conversation == null
                ? const Text('Trip conversation')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.tripTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${conversation.memberCount} members · ${conversation.routeLabel}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
          ),
          body: Column(
            children: [
              const _PrivacyNotice(),
              if (_conversationController.realtimeStatus ==
                  ChatRealtimeStatus.disconnected)
                const _ConnectionNotice(),
              Expanded(
                child: _ConversationBody(
                  controller: _conversationController,
                  scrollController: _scrollController,
                  currentUserId: chat.userId,
                  isBlocked: safety.isBlocked,
                ),
              ),
              _MessageComposer(
                controller: _messageController,
                onChanged: () => setState(() {}),
                onSend: _send,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ConversationBody extends StatelessWidget {
  const _ConversationBody({
    required this.controller,
    required this.scrollController,
    required this.currentUserId,
    required this.isBlocked,
  });

  final ConversationController controller;
  final ScrollController scrollController;
  final String currentUserId;
  final bool Function(String?) isBlocked;

  @override
  Widget build(BuildContext context) {
    if (controller.isLoading && controller.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.loadErrorMessage != null && controller.messages.isEmpty) {
      return _ConversationError(
        message: controller.loadErrorMessage!,
        onRetry: controller.retryLoad,
      );
    }
    if (controller.messages.isEmpty) {
      return const _EmptyConversation();
    }

    final messages = controller.messages;
    final hasHistoryLoader = controller.hasOlder || controller.isLoadingOlder;
    return ListView.builder(
      key: const PageStorageKey('conversation-message-list'),
      controller: scrollController,
      reverse: true,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      itemCount: messages.length + (hasHistoryLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return _HistoryLoader(
            isLoading: controller.isLoadingOlder,
            onLoad: controller.loadOlder,
          );
        }
        final messageIndex = messages.length - 1 - index;
        final message = messages[messageIndex];
        final previous = messageIndex > 0 ? messages[messageIndex - 1] : null;
        final startsGroup = !_sameMessageGroup(previous, message);
        final startsDay =
            previous == null || !_isSameDay(previous.sentAt, message.sentAt);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (startsDay) _DateDivider(date: message.sentAt),
            _MessageBubble(
              message: message,
              isMine: message.isMine(currentUserId),
              isBlockedSender: isBlocked(message.senderId),
              startsGroup: startsGroup,
              onRetry: () => controller.retry(message),
            ),
          ],
        );
      },
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  const _PrivacyNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      color: AppColors.greenSoft,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_outline_rounded, size: 15, color: AppColors.green),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'Only confirmed trip members can read this conversation.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.green, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectionNotice extends StatelessWidget {
  const _ConnectionNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chat-connection-notice'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      color: AppColors.terracottaSoft,
      child: const Text(
        'Reconnecting… New messages may be delayed.',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.ink, fontSize: 12),
      ),
    );
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Text(
              _formatMessageDate(date),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isBlockedSender,
    required this.startsGroup,
    required this.onRetry,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isBlockedSender;
  final bool startsGroup;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatMessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: AppColors.border),
          ),
          child: Text(
            message.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: AppColors.muted,
              fontSize: 12,
            ),
          ),
        ),
      );
    }

    if (isBlockedSender) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.visibility_off_outlined, size: 16),
              SizedBox(width: AppSpacing.xs),
              Text('Message hidden from a blocked member'),
            ],
          ),
        ),
      );
    }

    final senderName = message.senderName ?? 'Trip member';
    return Semantics(
      label:
          '${isMine ? 'You' : senderName}, ${message.body}, ${_formatMessageTime(message.sentAt)}',
      child: Padding(
        padding: EdgeInsets.only(
          top: startsGroup ? AppSpacing.xs : 2,
          bottom: 2,
        ),
        child: Row(
          mainAxisAlignment: isMine
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!isMine) ...[
              SizedBox(
                width: 30,
                child: startsGroup
                    ? _SenderAvatar(name: senderName)
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
            Flexible(
              child: Container(
                key: ValueKey('chat-message-${message.stableId}'),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.sizeOf(context).width * 0.74,
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  AppSpacing.sm,
                  AppSpacing.md,
                  AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: isMine ? AppColors.green : AppColors.surface,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(!isMine && !startsGroup ? 7 : 18),
                    topRight: Radius.circular(isMine && !startsGroup ? 7 : 18),
                    bottomLeft: const Radius.circular(18),
                    bottomRight: const Radius.circular(18),
                  ),
                  border: isMine ? null : Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine && startsGroup) ...[
                      Text(
                        senderName,
                        style: const TextStyle(
                          color: AppColors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                    ],
                    Text(
                      message.body,
                      style: TextStyle(
                        color: isMine ? Colors.white : AppColors.ink,
                        height: 1.32,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _formatMessageTime(message.sentAt),
                          style: TextStyle(
                            color: isMine
                                ? Colors.white.withValues(alpha: 0.72)
                                : AppColors.muted,
                            fontSize: 10,
                          ),
                        ),
                        if (isMine) ...[
                          const SizedBox(width: 4),
                          _DeliveryIcon(status: message.deliveryStatus),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (message.deliveryStatus == ChatDeliveryStatus.failed) ...[
              const SizedBox(width: 4),
              IconButton(
                key: ValueKey('retry-chat-message-${message.stableId}'),
                onPressed: onRetry,
                tooltip: 'Message failed. Tap to retry.',
                visualDensity: VisualDensity.compact,
                color: AppColors.error,
                icon: const Icon(Icons.refresh_rounded, size: 20),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SenderAvatar extends StatelessWidget {
  const _SenderAvatar({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return CircleAvatar(
      radius: 15,
      backgroundColor: AppColors.terracottaSoft,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _DeliveryIcon extends StatelessWidget {
  const _DeliveryIcon({required this.status});

  final ChatDeliveryStatus status;

  @override
  Widget build(BuildContext context) {
    return switch (status) {
      ChatDeliveryStatus.sending => Icon(
        Icons.schedule_rounded,
        size: 12,
        color: Colors.white.withValues(alpha: 0.72),
      ),
      ChatDeliveryStatus.sent => Icon(
        Icons.check_rounded,
        size: 13,
        color: Colors.white.withValues(alpha: 0.72),
      ),
      ChatDeliveryStatus.failed => const Icon(
        Icons.error_outline_rounded,
        size: 13,
        color: Colors.white,
      ),
    };
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.characters.length;
    final codePointLength = controller.text.trim().runes.length;
    final canSend = codePointLength > 0 && codePointLength <= 1000;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.border)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('chat-composer'),
                controller: controller,
                minLines: 1,
                maxLines: 5,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                keyboardType: TextInputType.multiline,
                onChanged: (_) => onChanged(),
                decoration: InputDecoration(
                  hintText: 'Message the group',
                  counterText: length >= 900 ? '$length / 1000' : '',
                  filled: true,
                  fillColor: AppColors.canvas,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Semantics(
              button: true,
              label: 'Send message',
              child: IconButton.filled(
                key: const ValueKey('send-chat-message'),
                onPressed: canSend ? onSend : null,
                tooltip: 'Send message',
                icon: const Icon(Icons.arrow_upward_rounded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryLoader extends StatelessWidget {
  const _HistoryLoader({required this.isLoading, required this.onLoad});

  final bool isLoading;
  final VoidCallback onLoad;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Center(
        child: isLoading
            ? const SizedBox.square(
                dimension: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : TextButton(onPressed: onLoad, child: const Text('Load earlier')),
      ),
    );
  }
}

class _ConversationError extends StatelessWidget {
  const _ConversationError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, color: AppColors.green),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.greenSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.waving_hand_outlined,
                color: AppColors.green,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Start planning together',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Share an arrival time, transport idea, or the first place you want to visit.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
      ),
    );
  }
}

bool _sameMessageGroup(ChatMessage? previous, ChatMessage current) {
  if (previous == null ||
      previous.type != ChatMessageType.member ||
      current.type != ChatMessageType.member ||
      previous.senderId != current.senderId ||
      !_isSameDay(previous.sentAt, current.sentAt)) {
    return false;
  }
  return current.sentAt.difference(previous.sentAt) <=
      const Duration(minutes: 5);
}

bool _isSameDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

String _formatMessageDate(DateTime value) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final date = DateTime(value.year, value.month, value.day);
  final difference = today.difference(date).inDays;
  if (difference == 0) {
    return 'Today';
  }
  if (difference == 1) {
    return 'Yesterday';
  }
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[value.month - 1]} ${value.day}, ${value.year}';
}

String _formatMessageTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
