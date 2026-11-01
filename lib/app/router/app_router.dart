import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/app_auth_state.dart';
import '../app_shell.dart';
import '../providers/app_providers.dart';
import '../../features/auth/presentation/welcome_screen.dart';
import '../../features/auth/presentation/check_email_screen.dart';
import '../../features/beta/presentation/beta_feedback_screen.dart';
import '../../features/explore/presentation/explore_screen.dart';
import '../../features/join_requests/presentation/trip_requests_screen.dart';
import '../../features/logistics/presentation/trip_logistics_screen.dart';
import '../../features/messages/presentation/messages_screen.dart';
import '../../features/messages/presentation/conversation_screen.dart';
import '../../features/notifications/presentation/notifications_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/profile/presentation/profile_onboarding_screen.dart';
import '../../features/profile/domain/traveler_action_target.dart';
import '../../features/profile/presentation/member_profile_screen.dart';
import '../../features/safety/presentation/safety_center_screen.dart';
import '../../features/trips/presentation/trips_screen.dart';
import '../../features/trips/presentation/create_trip_screen.dart';
import '../../features/trips/presentation/route_explorer_screen.dart';
import '../../features/trips/presentation/trip_detail_screen.dart';
import 'startup_screen.dart';

abstract final class AppRoutes {
  static const startup = '/startup';
  static const welcome = '/welcome';
  static const checkEmail = '/check-email';
  static const onboarding = '/onboarding';
  static const explore = '/explore';
  static const trips = '/trips';
  static const createTrip = '/trips/new';
  static const messages = '/messages';
  static const profile = '/profile';
  static const safety = '/safety';
  static const betaFeedback = '/beta-feedback';
  static const notifications = '/notifications';
  static const editProfile = '/profile/edit';

  static String tripDetails(String tripId) => '/trip/$tripId';
  static String editTrip(String tripId) => '/trip/$tripId/edit';
  static String tripRoute(String tripId) => '/trip/$tripId/route';
  static String tripRequests(String tripId) => '/trip/$tripId/requests';
  static String tripLogistics(String tripId) => '/trip/$tripId/logistics';
  static String conversation(String conversationId) =>
      '/conversation/$conversationId';

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

      if (authState.status == AppSessionStatus.loading ||
          authState.status == AppSessionStatus.failure) {
        return location == AppRoutes.startup ? null : AppRoutes.startup;
      }

      if (authState.status == AppSessionStatus.signedOut) {
        final isPublicRoute =
            location == AppRoutes.welcome || location == AppRoutes.checkEmail;
        return isPublicRoute ? null : AppRoutes.welcome;
      }

      if (authState.status == AppSessionStatus.onboardingRequired) {
        return location == AppRoutes.onboarding ? null : AppRoutes.onboarding;
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
        builder: (context, state) => const ProfileOnboardingScreen(),
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
          return CreateTripScreen(tripId: state.pathParameters['tripId']);
        },
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) {
          return const ProfileOnboardingScreen(isEditing: true);
        },
      ),
      GoRoute(
        path: AppRoutes.createTrip,
        builder: (context, state) => const CreateTripScreen(),
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

  ref.onDispose(router.dispose);
  ref.onDispose(sessionStatus.dispose);
  return router;
});
