import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/check_email_screen.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/beta/presentation/beta_feedback_screen.dart';
import '../../features/explore/presentation/explore_screen.dart';
import '../../features/explore/presentation/trip_map_screen.dart';
import '../../features/join_requests/presentation/trip_requests_screen.dart';
import '../../features/legal/domain/legal_documents.dart';
import '../../features/legal/presentation/legal_screen.dart';
import '../../features/logistics/presentation/trip_logistics_screen.dart';
import '../../features/messages/presentation/conversation_screen.dart';
import '../../features/messages/presentation/messages_screen.dart';
import '../../features/notifications/domain/app_notification.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/domain/traveler_action_target.dart';
import '../../features/profile/presentation/member_profile_screen.dart';
import '../../features/profile/presentation/edit_profile_screen.dart';
import '../../features/profile/presentation/profile_setup_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/safety/presentation/safety_center_screen.dart';
import '../../features/trips/presentation/edit_trip_screen.dart';
import '../../features/trips/presentation/plan_trip_screen.dart';
import '../../features/trips/presentation/route_explorer_screen.dart';
import '../../features/trips/presentation/trip_detail_screen.dart';
import '../../features/trips/presentation/trips_screen.dart';
import '../app_shell.dart';
import '../auth/app_auth_state.dart';
import '../providers/app_providers.dart';
import 'startup_screen.dart';

abstract final class AppRoutes {
  static const startup = '/startup';
  static const welcome = '/welcome';
  static const checkEmail = '/check-email';
  static const onboarding = '/onboarding';
  static const explore = '/explore';
  static const tripMap = '/explore/map';
  static const trips = '/trips';
  static const createTrip = '/trips/new';
  static const messages = '/messages';
  static const profile = '/profile';
  static const safety = '/safety';
  static const betaFeedback = '/beta-feedback';
  static const notifications = '/notifications';
  static const editProfile = '/profile/edit';
  static const terms = '/legal/terms';
  static const privacy = '/legal/privacy';

  static String tripDetails(String tripId) => '/trip/$tripId';
  static String editTrip(String tripId) => '/trip/$tripId/edit';
  static String tripRoute(String tripId) => '/trip/$tripId/route';
  static String tripRequests(String tripId) => '/trip/$tripId/requests';
  static String tripLogistics(String tripId) => '/trip/$tripId/logistics';
  static String conversation(String conversationId) =>
      '/conversation/$conversationId';

  /// Where a notification leads, or null when it has no related trip.
  static String? notificationTarget(NotificationKind kind, String? tripId) {
    if (tripId == null) {
      return null;
    }
    return kind == NotificationKind.joinRequestReceived
        ? tripRequests(tripId)
        : tripDetails(tripId);
  }

  static String memberProfile(
    String userId, {
    String? tripId,
    String? conversationId,
    bool openedFromConversation = false,
  }) {
    return Uri(
      path: '/member/$userId',
      queryParameters: {
        'trip': ?tripId,
        'conversation': ?conversationId,
        if (openedFromConversation) 'from': 'conversation',
      },
    ).toString();
  }
}

// Redirects depend only on the session status. Refreshing on every profile change
// would also discard a pop made while the refresh is being processed.
class _SessionStatusListenable extends ChangeNotifier {
  _SessionStatusListenable(this._authState) : _status = _authState.status {
    _authState.addListener(_onChanged);
  }

  final AppAuthState _authState;
  AppSessionStatus _status;

  void _onChanged() {
    if (_authState.status != _status) {
      _status = _authState.status;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _authState.removeListener(_onChanged);
    super.dispose();
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(appAuthStateProvider);
  final sessionStatus = _SessionStatusListenable(authState);

  final router = GoRouter(
    initialLocation: AppRoutes.explore,
    refreshListenable: sessionStatus,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isLegalRoute =
          location == AppRoutes.terms || location == AppRoutes.privacy;

      if (authState.status == AppSessionStatus.loading ||
          authState.status == AppSessionStatus.failure) {
        return location == AppRoutes.startup ? null : AppRoutes.startup;
      }

      if (authState.status == AppSessionStatus.signedOut) {
        final isPublicRoute =
            location == AppRoutes.welcome ||
            location == AppRoutes.checkEmail ||
            isLegalRoute;
        return isPublicRoute ? null : AppRoutes.welcome;
      }

      if (authState.status == AppSessionStatus.onboardingRequired) {
        return location == AppRoutes.onboarding || isLegalRoute
            ? null
            : AppRoutes.onboarding;
      }

      if (location == AppRoutes.welcome ||
          location == AppRoutes.checkEmail ||
          location == AppRoutes.onboarding ||
          location == AppRoutes.startup) {
        return AppRoutes.explore;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.startup,
        builder: (context, state) => StartupScreen(authState: authState),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),
      GoRoute(
        path: AppRoutes.checkEmail,
        builder: (context, state) {
          return CheckEmailScreen(
            email: state.uri.queryParameters['email'] ?? '',
          );
        },
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: AppRoutes.tripMap,
        builder: (context, state) => const TripMapScreen(),
      ),
      GoRoute(
        path: '/trip/:tripId/route',
        builder: (context, state) {
          return RouteExplorerScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        path: '/trip/:tripId',
        builder: (context, state) {
          return TripDetailScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        path: '/trip/:tripId/requests',
        builder: (context, state) {
          return TripRequestsScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        path: '/trip/:tripId/logistics',
        builder: (context, state) {
          return TripLogisticsScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        path: '/trip/:tripId/edit',
        builder: (context, state) {
          return EditTripScreen(tripId: state.pathParameters['tripId']!);
        },
      ),
      GoRoute(
        path: AppRoutes.terms,
        builder: (context, state) => const LegalScreen(document: termsOfUse),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        builder: (context, state) => const LegalScreen(document: privacyPolicy),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.createTrip,
        builder: (context, state) => const PlanTripScreen(),
      ),
      GoRoute(
        path: AppRoutes.safety,
        builder: (context, state) => const SafetyCenterScreen(),
      ),
      GoRoute(
        path: AppRoutes.betaFeedback,
        builder: (context, state) => const BetaFeedbackScreen(),
      ),
      GoRoute(
        path: '/member/:userId',
        builder: (context, state) {
          return MemberProfileScreen(
            userId: state.pathParameters['userId']!,
            tripId: state.uri.queryParameters['trip'],
            conversationId: state.uri.queryParameters['conversation'],
            openedFromConversation:
                state.uri.queryParameters['from'] == 'conversation',
            fallback: state.extra is TravelerActionTarget
                ? state.extra! as TravelerActionTarget
                : null,
          );
        },
      ),
      GoRoute(
        path: '/conversation/:conversationId',
        builder: (context, state) {
          return ConversationScreen(
            conversationId: state.pathParameters['conversationId']!,
          );
        },
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return AppShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.explore,
                builder: (context, state) => const ExploreScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.trips,
                builder: (context, state) => const TripsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.messages,
                builder: (context, state) => const MessagesScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  ref.watch(pushControllerProvider).attach((open) {
    final notificationId = open.notificationId;
    if (notificationId != null) {
      unawaited(
        ref.read(notificationControllerProvider).markReadById(notificationId),
      );
    }
    final kind = NotificationKind.fromStorage(open.kind);
    final target = kind == null
        ? null
        : AppRoutes.notificationTarget(kind, open.tripId);
    router.push(target ?? AppRoutes.notifications);
  });

  ref.onDispose(router.dispose);
  ref.onDispose(sessionStatus.dispose);
  return router;
});
