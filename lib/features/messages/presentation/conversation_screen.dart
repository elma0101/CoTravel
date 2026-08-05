import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/analytics/product_analytics.dart';
import '../application/chat_controller.dart';
import '../domain/trip_conversation.dart';

class ConversationScreen extends ConsumerStatefulWidget {
  const ConversationScreen({required this.conversationId, super.key});

  final String conversationId;

  @override
  ConsumerState<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends ConsumerState<ConversationScreen> {
  final _messageController = TextEditingController();
  late ChatController _chatController;
  late Stream<List<ChatMessage>> _messages;

  @override
  void initState() {
    super.initState();
    _chatController = ref.read(chatControllerProvider);
    _messages = _chatController.watchMessages(widget.conversationId);
    unawaited(_chatController.markRead(widget.conversationId));
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
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final body = _messageController.text.trim();
    if (body.isEmpty) {
      return;
    }
    try {
      await _chatController.sendMessage(
        conversationId: widget.conversationId,
        body: body,
      );
      _messageController.clear();
      if (mounted) {
        setState(() {});
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _chatController.errorMessage ?? 'Message could not be sent.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(chatControllerProvider);
    final safety = ref.watch(safetyControllerProvider);

    return ListenableBuilder(
      listenable: Listenable.merge([controller, safety]),
      builder: (context, child) {
        final conversation = controller.conversationById(widget.conversationId);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 0,
            title: conversation == null
                ? const Text('Trip conversation')
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.tripTitle,
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
              Expanded(
                child: StreamBuilder<List<ChatMessage>>(
                  stream: _messages,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final messages = snapshot.data!;
                    if (messages.isEmpty) {
                      return const _EmptyConversation();
                    }
                    return ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.lg,
                      ),
                      itemCount: messages.length,
                      itemBuilder: (context, index) {
                        final message = messages[messages.length - 1 - index];
                        return _MessageBubble(
                          message: message,
                          isMine: message.isMine(controller.userId),
                          isBlockedSender: safety.isBlocked(message.senderId),
                        );
                      },
                    );
                  },
                ),
              ),
              _MessageComposer(
                controller: _messageController,
                isSending: controller.isSending,
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

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.isBlockedSender,
  });

  final ChatMessage message;
  final bool isMine;
  final bool isBlockedSender;

  @override
  Widget build(BuildContext context) {
    if (message.type == ChatMessageType.system) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Text(
          message.body,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: AppColors.muted,
            fontSize: 12,
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

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        key: ValueKey('chat-message-${message.id}'),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isMine ? AppColors.green : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine ? null : Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isMine) ...[
              Text(
                message.senderName ?? 'Trip member',
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
            ],
            Text(
              message.body,
              style: TextStyle(color: isMine ? Colors.white : AppColors.ink),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                _formatMessageTime(message.sentAt),
                style: TextStyle(
                  color: isMine
                      ? Colors.white.withValues(alpha: 0.72)
                      : AppColors.muted,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageComposer extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.isSending,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool isSending;
  final VoidCallback onChanged;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty && !isSending;
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
                maxLines: 4,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => onChanged(),
                onSubmitted: (_) {
                  if (canSend) {
                    onSend();
                  }
                },
                decoration: const InputDecoration(
                  hintText: 'Message the group',
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton.filled(
              key: const ValueKey('send-chat-message'),
              onPressed: canSend ? onSend : null,
              tooltip: 'Send message',
              icon: isSending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
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
        child: Text(
          'The group is ready. Start with the first planning detail.',
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
      ),
    );
  }
}

String _formatMessageTime(DateTime value) {
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}
