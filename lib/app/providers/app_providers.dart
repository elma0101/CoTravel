import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/product_analytics.dart';
import '../../features/beta/application/beta_feedback_controller.dart';
import '../../features/beta/data/beta_feedback_repository.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/domain/user_profile.dart';
import '../../core/services/external_link_launcher.dart';
import '../../features/join_requests/application/join_request_controller.dart';
import '../../features/join_requests/data/join_request_repository.dart';
import '../../features/logistics/application/logistics_controller.dart';
import '../../features/logistics/data/logistics_repository.dart';
import '../../features/messages/application/chat_controller.dart';
import '../../features/messages/data/chat_repository.dart';
import '../../features/safety/application/safety_controller.dart';
import '../../features/safety/data/safety_repository.dart';
import '../../features/trips/application/trip_catalog_controller.dart';
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

final betaFeedbackRepositoryProvider = Provider<BetaFeedbackRepository>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return client == null
      ? PreviewBetaFeedbackRepository()
      : SupabaseBetaFeedbackRepository(client);
});

final betaFeedbackControllerProvider = Provider<BetaFeedbackController>((ref) {
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

final tripCatalogProvider = Provider<TripCatalogController>((ref) {
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
  final profile = ref.watch(appAuthStateProvider).profile;
  final controller = ChatController(
    repository: ref.watch(chatRepositoryProvider),
    userId: profile?.id ?? 'preview-user',
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
  );
});

final joinRequestControllerProvider = Provider<JoinRequestController>((ref) {
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
