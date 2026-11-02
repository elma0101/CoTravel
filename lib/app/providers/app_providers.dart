import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/product_analytics.dart';
import '../../core/services/external_link_launcher.dart';
import '../../features/beta/application/beta_feedback_controller.dart';
import '../../features/beta/data/beta_feedback_repository.dart';
import '../../features/join_requests/application/join_request_controller.dart';
import '../../features/join_requests/data/join_request_repository.dart';
import '../../features/logistics/application/logistics_controller.dart';
import '../../features/logistics/data/logistics_repository.dart';
import '../../features/messages/application/chat_controller.dart';
import '../../features/messages/data/chat_repository.dart';
import '../../features/notifications/application/notification_controller.dart';
import '../../features/notifications/application/push_controller.dart';
import '../../features/notifications/data/notification_repository.dart';
import '../../features/notifications/data/push_messaging.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../features/safety/application/safety_controller.dart';
import '../../features/safety/data/safety_repository.dart';
import '../../features/trips/application/trip_catalog_controller.dart';
import '../../features/trips/data/place_search.dart';
import '../../features/trips/data/trip_repository.dart';
import '../auth/app_auth_state.dart';
import '../config/app_config.dart';

final appConfigProvider = Provider<AppConfig>((ref) {
  throw StateError('AppConfig has not been initialized.');
});

final supabaseClientProvider = Provider<SupabaseClient?>((ref) => null);

final productAnalyticsProvider = Provider<ProductAnalytics>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewProductAnalytics()
      : SupabaseProductAnalytics(client);
});

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewProfileRepository()
      : SupabaseProfileRepository(client);
});

final tripRepositoryProvider = Provider<TripRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewTripRepository()
      : SupabaseTripRepository(client);
});

// Previews and tests stay offline with the built-in places.
final placeSearchProvider = Provider<PlaceSearch>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null ? const BuiltInPlaceSearch() : PhotonPlaceSearch();
});

final betaFeedbackRepositoryProvider = Provider<BetaFeedbackRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewBetaFeedbackRepository()
      : SupabaseBetaFeedbackRepository(client);
});

final betaFeedbackControllerProvider = Provider<BetaFeedbackController>((ref) {
  ref.watch(sessionUserIdProvider);
  final controller = BetaFeedbackController(
    ref.watch(betaFeedbackRepositoryProvider),
  );
  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

final appAuthStateProvider = Provider<AppAuthState>((ref) {
  final config = ref.watch(appConfigProvider);
  final controller = AppAuthState(
    supabaseClient: ref.watch(supabaseClientProvider),
    profileRepository: ref.watch(profileRepositoryProvider),
    previewAuthEnabled: config.previewAuthEnabled,
    authRedirectUrl: 'com.cotravel.app://login-callback',
    analytics: ref.watch(productAnalyticsProvider),
  );

  ref.onDispose(controller.dispose);
  return controller;
});

class _SessionUserId extends Notifier<String?> {
  @override
  String? build() {
    final authState = ref.watch(appAuthStateProvider);
    void update() => state = authState.profile?.id;
    authState.addListener(update);
    ref.onDispose(() => authState.removeListener(update));
    return authState.profile?.id;
  }
}

/// Everything holding one user's data watches this, so it is rebuilt when another
/// account signs in rather than keeping the previous user's id and rows.
final sessionUserIdProvider = NotifierProvider<_SessionUserId, String?>(
  _SessionUserId.new,
);

final tripCatalogProvider = Provider<TripCatalogController>((ref) {
  ref.watch(sessionUserIdProvider);
  final authState = ref.watch(appAuthStateProvider);
  final profile = authState.profile ?? const UserProfile.preview();
  final controller = TripCatalogController(
    repository: ref.watch(tripRepositoryProvider),
    userId: profile.id,
    hostProfile: profile,
    analytics: ref.watch(productAnalyticsProvider),
  );

  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

final safetyRepositoryProvider = Provider<SafetyRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewSafetyRepository()
      : SupabaseSafetyRepository(client);
});

final safetyControllerProvider = Provider<SafetyController>((ref) {
  ref.watch(sessionUserIdProvider);
  final controller = SafetyController(
    repository: ref.watch(safetyRepositoryProvider),
    tripCatalog: ref.watch(tripCatalogProvider),
    analytics: ref.watch(productAnalyticsProvider),
  );
  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>((ref) {
  return const SystemExternalLinkLauncher();
});

final logisticsRepositoryProvider = Provider<LogisticsRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabaseLogisticsRepository(client);
  }
  return PreviewLogisticsRepository(
    tripRepository: ref.watch(tripRepositoryProvider) as PreviewTripRepository,
  );
});

final logisticsControllerProvider = Provider<LogisticsController>((ref) {
  ref.watch(sessionUserIdProvider);
  final controller = LogisticsController(
    repository: ref.watch(logisticsRepositoryProvider),
    tripCatalog: ref.watch(tripCatalogProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabaseChatRepository(client);
  }
  final repository = PreviewChatRepository();
  ref.onDispose(repository.dispose);
  return repository;
});

final chatControllerProvider = Provider<ChatController>((ref) {
  ref.watch(sessionUserIdProvider);
  final profile = ref.watch(appAuthStateProvider).profile;
  final controller = ChatController(
    repository: ref.watch(chatRepositoryProvider),
    userId: profile?.id ?? 'preview-user',
  );
  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewNotificationRepository()
      : SupabaseNotificationRepository(client);
});

final notificationControllerProvider = Provider<NotificationController>((ref) {
  ref.watch(sessionUserIdProvider);
  final controller = NotificationController(
    repository: ref.watch(notificationRepositoryProvider),
  );
  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

final joinRequestRepositoryProvider = Provider<JoinRequestRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client != null) {
    return SupabaseJoinRequestRepository(client);
  }
  final chatRepository =
      ref.watch(chatRepositoryProvider) as PreviewChatRepository;
  return PreviewJoinRequestRepository(
    tripRepository: ref.watch(tripRepositoryProvider) as PreviewTripRepository,
    onConfirmed: chatRepository.createForConfirmedRequest,
    onLeft: chatRepository.removeForDepartedTraveler,
  );
});

final joinRequestControllerProvider = Provider<JoinRequestController>((ref) {
  ref.watch(sessionUserIdProvider);
  final authState = ref.watch(appAuthStateProvider);
  final profile = authState.profile ?? const UserProfile.preview();
  final controller = JoinRequestController(
    repository: ref.watch(joinRequestRepositoryProvider),
    userId: profile.id,
    profile: profile,
    tripCatalog: ref.watch(tripCatalogProvider),
    refreshChats: ref.watch(chatControllerProvider).load,
    analytics: ref.watch(productAnalyticsProvider),
  );

  unawaited(controller.load());
  ref.onDispose(controller.dispose);
  return controller;
});

// Push is Android only for now. iOS needs an APNs key from a paid Apple account.
final pushMessagingProvider = Provider<PushMessaging>((ref) {
  final hasBackend = ref.watch(supabaseClientProvider) != null;
  return hasBackend && defaultTargetPlatform == TargetPlatform.android
      ? FirebasePushMessaging()
      : const NoopPushMessaging();
});

final pushTokenRepositoryProvider = Provider<PushTokenRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? const NoopPushTokenRepository()
      : SupabasePushTokenRepository(client);
});

final pushControllerProvider = Provider<PushController>((ref) {
  final controller = PushController(
    authState: ref.watch(appAuthStateProvider),
    messaging: ref.watch(pushMessagingProvider),
    tokens: ref.watch(pushTokenRepositoryProvider),
  );
  unawaited(controller.start());
  ref.onDispose(controller.dispose);
  return controller;
});
