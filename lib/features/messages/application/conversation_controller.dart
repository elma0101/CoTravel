import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/chat_repository.dart';
import '../domain/trip_conversation.dart';

class ConversationController extends ChangeNotifier {
  factory ConversationController({
    required ChatRepository repository,
    required String conversationId,
    required String userId,
    required String userName,
    required VoidCallback onInboxChanged,
    required VoidCallback onConversationRead,
  }) {
    return ConversationController._(
      repository,
      conversationId,
      userId,
      userName,
      onInboxChanged,
      onConversationRead,
    );
  }

  ConversationController._(
    this._repository,
    this.conversationId,
    this.userId,
    this.userName,
    this._onInboxChanged,
    this._onConversationRead,
  );

  static const _pageSize = 40;

  final ChatRepository _repository;
  final String conversationId;
  final String userId;
  final String userName;
  final VoidCallback _onInboxChanged;
  final VoidCallback _onConversationRead;
  final Random _random = Random.secure();

  List<ChatMessage> _messages = const [];
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _hasOlder = false;
  bool _isActive = true;
  String? _loadErrorMessage;
  ChatRealtimeStatus _realtimeStatus = ChatRealtimeStatus.connecting;
  StreamSubscription<ChatRealtimeEvent>? _realtimeSubscription;
  Timer? _readDebounce;
  bool _disposed = false;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  bool get isLoadingOlder => _isLoadingOlder;
  bool get hasOlder => _hasOlder;
  String? get loadErrorMessage => _loadErrorMessage;
  ChatRealtimeStatus get realtimeStatus => _realtimeStatus;
  bool get hasFailedMessages => _messages.any(
    (message) => message.deliveryStatus == ChatDeliveryStatus.failed,
  );

  Future<void> start() async {
    await _realtimeSubscription?.cancel();
    _realtimeSubscription = _repository
        .watchConversation(conversationId)
        .listen(_handleRealtimeEvent, onError: (_) => _setDisconnected());
    await _loadInitial();
  }

  Future<void> retryLoad() => _loadInitial();

  Future<void> loadOlder() async {
    if (_isLoading || _isLoadingOlder || !_hasOlder || _messages.isEmpty) {
      return;
    }
    final oldest = _messages.firstWhere(
      (message) => message.deliveryStatus == ChatDeliveryStatus.sent,
      orElse: () => _messages.first,
    );
    _isLoadingOlder = true;
    notifyListeners();
    try {
      final page = await _repository.fetchMessages(
        conversationId: conversationId,
        before: ChatMessageCursor(sentAt: oldest.sentAt, messageId: oldest.id),
        limit: _pageSize,
      );
      _hasOlder = page.hasMore;
      _mergeMessages(page.messages);
    } on Object {
      // Keep the loaded conversation usable; the user can scroll up to retry.
    } finally {
      _isLoadingOlder = false;
      _notifyIfMounted();
    }
  }

  Future<void> send(String body) async {
    final trimmed = body.trim();
    if (trimmed.isEmpty || trimmed.runes.length > 1000) {
      throw ArgumentError('Messages must contain 1 to 1000 characters.');
    }

    final clientId = _newClientId();
    final optimistic = ChatMessage(
      id: 'local-$clientId',
      conversationId: conversationId,
      senderId: userId,
      senderName: userName,
      body: trimmed,
      type: ChatMessageType.member,
      sentAt: DateTime.now(),
      clientId: clientId,
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    _mergeMessages([optimistic]);
    await _deliver(optimistic);
  }

  Future<void> retry(ChatMessage message) async {
    if (message.deliveryStatus != ChatDeliveryStatus.failed ||
        message.clientId == null) {
      return;
    }
    final retrying = message.copyWith(
      deliveryStatus: ChatDeliveryStatus.sending,
    );
    _replaceByStableId(retrying);
    await _deliver(retrying);
  }

  void setActive(bool isActive) {
    _isActive = isActive;
    if (isActive) {
      _scheduleMarkRead();
    }
  }

  Future<void> _loadInitial() async {
    _isLoading = true;
    _loadErrorMessage = null;
    _notifyIfMounted();
    try {
      final page = await _repository.fetchMessages(
        conversationId: conversationId,
        limit: _pageSize,
      );
      _hasOlder = page.hasMore;
      _mergeMessages(page.messages);
      _scheduleMarkRead();
    } on Object {
      _loadErrorMessage =
          'Messages could not be loaded. Check your connection.';
    } finally {
      _isLoading = false;
      _notifyIfMounted();
    }
  }

  Future<void> _deliver(ChatMessage message) async {
    try {
      final delivered = await _repository.sendMessage(
        conversationId: conversationId,
        body: message.body,
        clientId: message.clientId!,
      );
      _mergeMessages([delivered]);
      _onInboxChanged();
    } on Object {
      final current = _messages.where(
        (candidate) => candidate.stableId == message.stableId,
      );
      final wasConfirmedByRealtime =
          current.isNotEmpty &&
          current.first.deliveryStatus == ChatDeliveryStatus.sent &&
          !current.first.id.startsWith('local-');
      if (!wasConfirmedByRealtime) {
        _replaceByStableId(
          message.copyWith(deliveryStatus: ChatDeliveryStatus.failed),
        );
      }
    }
  }

  void _handleRealtimeEvent(ChatRealtimeEvent event) {
    _realtimeStatus = event.status;
    final message = event.message;
    if (message != null) {
      _mergeMessages([message]);
      _onInboxChanged();
      if (!message.isMine(userId)) {
        _scheduleMarkRead();
      }
    } else {
      _notifyIfMounted();
    }
  }

  void _setDisconnected() {
    _realtimeStatus = ChatRealtimeStatus.disconnected;
    _notifyIfMounted();
  }

  void _mergeMessages(Iterable<ChatMessage> incoming) {
    final merged = [..._messages];
    for (final next in incoming) {
      final index = merged.indexWhere(
        (current) =>
            current.id == next.id ||
            (next.clientId != null && current.clientId == next.clientId),
      );
      if (index < 0) {
        merged.add(next);
      } else {
        merged[index] = next;
      }
    }
    merged.sort((left, right) {
      final byTime = left.sentAt.compareTo(right.sentAt);
      return byTime != 0 ? byTime : left.id.compareTo(right.id);
    });
    _messages = merged;
    _notifyIfMounted();
  }

  void _replaceByStableId(ChatMessage replacement) {
    final updated = [..._messages];
    final index = updated.indexWhere(
      (message) => message.stableId == replacement.stableId,
    );
    if (index >= 0) {
      updated[index] = replacement;
      _messages = updated;
      _notifyIfMounted();
    }
  }

  void _scheduleMarkRead() {
    if (!_isActive || _messages.isEmpty) {
      return;
    }
    _onConversationRead();
    _readDebounce?.cancel();
    _readDebounce = Timer(const Duration(milliseconds: 350), () async {
      final latest = _messages.last;
      try {
        await _repository.markRead(
          conversationId: conversationId,
          through: latest.sentAt,
        );
        _onInboxChanged();
      } on Object {
        // A read receipt should never make the conversation unusable.
      }
    });
  }

  String _newClientId() {
    final randomPart = List.generate(
      12,
      (_) => _random.nextInt(16).toRadixString(16),
    ).join();
    return '${DateTime.now().microsecondsSinceEpoch}-$randomPart';
  }

  void _notifyIfMounted() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _readDebounce?.cancel();
    unawaited(_realtimeSubscription?.cancel());
    super.dispose();
  }
}
