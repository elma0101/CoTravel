import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/product_analytics.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/l10n/auth_errors.dart';
import '../../core/l10n/server_errors.dart';
import '../../features/legal/domain/legal_documents.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/domain/user_profile.dart';

enum AppSessionStatus {
  loading,
  signedOut,
  onboardingRequired,
  authenticated,
  failure,
}

class AppAuthState extends ChangeNotifier {
  AppAuthState({
    required SupabaseClient? supabaseClient,
    required ProfileRepository profileRepository,
    required bool previewAuthEnabled,
    required String authRedirectUrl,
    ProductAnalytics analytics = const NoopProductAnalytics(),
  }) : this._(
         supabaseClient,
         profileRepository,
         previewAuthEnabled,
         authRedirectUrl,
         analytics,
       );

  AppAuthState._(
    this._supabaseClient,
    this.profileRepository,
    this.previewAuthEnabled,
    this.authRedirectUrl,
    this._analytics,
  ) {
    if (_supabaseClient == null) {
      _status = AppSessionStatus.signedOut;
    } else {
      _authSubscription = _supabaseClient.auth.onAuthStateChange.listen((
        state,
      ) {
        unawaited(_synchronizeSession(state.session));
      });
      unawaited(_synchronizeSession(_supabaseClient.auth.currentSession));
    }
  }

  AppAuthState.preview({
    bool initiallyAuthenticated = false,
    bool onboardingComplete = true,
  }) : _supabaseClient = null,
       profileRepository = PreviewProfileRepository(),
       previewAuthEnabled = true,
       authRedirectUrl = 'com.cotravel.app://login-callback',
       _analytics = const NoopProductAnalytics(),
       _userId = initiallyAuthenticated ? 'preview-user' : null,
       _status = !initiallyAuthenticated
           ? AppSessionStatus.signedOut
           : onboardingComplete
           ? AppSessionStatus.authenticated
           : AppSessionStatus.onboardingRequired,
       _profile = !initiallyAuthenticated
           ? null
           : onboardingComplete
           ? const UserProfile.preview()
           : const UserProfile.incompletePreview();

  final SupabaseClient? _supabaseClient;
  final ProfileRepository profileRepository;
  final bool previewAuthEnabled;
  final String authRedirectUrl;
  final ProductAnalytics _analytics;

  StreamSubscription<AuthState>? _authSubscription;
  String? _userId;
  AppSessionStatus _status = AppSessionStatus.loading;
  UserProfile? _profile;
  String? _errorMessage;
  int _synchronizationGeneration = 0;
  bool _hasTrackedVerifiedProfile = false;

  AppSessionStatus get status => _status;
  UserProfile? get profile => _profile;
  String? get errorMessage => _errorMessage;
  bool get isReady =>
      _status != AppSessionStatus.loading &&
      _status != AppSessionStatus.failure;
  bool get isAuthenticated => _status == AppSessionStatus.authenticated;
  bool get needsOnboarding => _status == AppSessionStatus.onboardingRequired;
  bool get hasBackend => _supabaseClient != null;

  Future<void> sendMagicLink(String email) async {
    final client = _requireClient();
    await client.auth.signInWithOtp(
      email: email.trim(),
      emailRedirectTo: authRedirectUrl,
    );
  }

  Future<bool> linkLinkedIn() async {
    final client = _requireClient();
    return client.auth.linkIdentity(
      OAuthProvider.linkedinOidc,
      redirectTo: authRedirectUrl,
    );
  }

  Future<void> refreshProfile() async {
    await _synchronizeSession(_supabaseClient?.auth.currentSession);
  }

  Future<void> completeProfile({
    required ProfileDraft draft,
    Uint8List? avatarBytes,
    String avatarExtension = 'jpg',
  }) async {
    final userId = _supabaseClient?.auth.currentUser?.id ?? 'preview-user';
    // The status stays put until the profile is saved, so a failure leaves
    // the sign-up screens, and what was chosen in them, where they were.
    _errorMessage = null;

    try {
      await profileRepository.acceptTerms(currentTermsVersion);
      _profile = await profileRepository.completeProfile(
        userId: userId,
        draft: draft,
        avatarBytes: avatarBytes,
        avatarExtension: avatarExtension,
      );
      _status = AppSessionStatus.authenticated;
      unawaited(_analytics.track(ProductEvent.profileCompleted));
      notifyListeners();
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      _status = AppSessionStatus.onboardingRequired;
      notifyListeners();
      rethrow;
    }
  }

  // Unlike completeProfile, this keeps the session status so the router stays
  // on the current screen.
  Future<void> updateProfile({
    required ProfileDraft draft,
    Uint8List? avatarBytes,
    String avatarExtension = 'jpg',
  }) async {
    final userId = _supabaseClient?.auth.currentUser?.id ?? 'preview-user';
    _profile = await profileRepository.completeProfile(
      userId: userId,
      draft: draft,
      avatarBytes: avatarBytes,
      avatarExtension: avatarExtension,
    );
    notifyListeners();
  }

  Future<void> signInForPreview() async {
    if (!previewAuthEnabled) {
      throw StateError('Preview authentication is disabled.');
    }

    _userId = 'preview-user';
    _profile = const UserProfile.preview();
    _status = AppSessionStatus.authenticated;
    unawaited(_analytics.track(ProductEvent.previewSignedIn));
    notifyListeners();
  }

  Future<void> signOut() async {
    if (_supabaseClient != null) {
      await _supabaseClient.auth.signOut();
      return;
    }

    _userId = null;
    _profile = null;
    _status = AppSessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> deleteAccount() async {
    final userId = _supabaseClient?.auth.currentUser?.id ?? 'preview-user';
    await profileRepository.deleteAccount(userId);
    if (_supabaseClient != null) {
      // The session's user no longer exists, so only local sign-out can succeed.
      await _supabaseClient.auth.signOut(scope: SignOutScope.local);
      return;
    }

    _userId = null;
    _profile = null;
    _status = AppSessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> _synchronizeSession(Session? session) {
    return synchronizeUser(session?.user.id);
  }

  @visibleForTesting
  Future<void> synchronizeUser(String? userId) async {
    final generation = ++_synchronizationGeneration;

    if (userId == null) {
      _userId = null;
      _profile = null;
      _errorMessage = null;
      _status = AppSessionStatus.signedOut;
      notifyListeners();
      return;
    }

    // Token refreshes and identity linking keep the same user. Passing through
    // loading would send the router to the startup screen and rebuild the
    // current one, losing what was typed in it.
    final isRefresh =
        userId == _userId &&
        (_status == AppSessionStatus.onboardingRequired ||
            _status == AppSessionStatus.authenticated);
    _userId = userId;
    if (!isRefresh) {
      _status = AppSessionStatus.loading;
      _errorMessage = null;
      notifyListeners();
    }

    try {
      final isVerified = await profileRepository.syncLinkedInVerification(
        userId,
      );
      if (isVerified && !_hasTrackedVerifiedProfile) {
        _hasTrackedVerifiedProfile = true;
        unawaited(_analytics.track(ProductEvent.profileVerified));
      }
      final nextProfile = await profileRepository.fetchProfile(userId);
      if (generation != _synchronizationGeneration) {
        return;
      }

      _profile = nextProfile;
      _status =
          nextProfile?.isOnboardingComplete == true &&
              nextProfile?.hasAcceptedCurrentTerms == true
          ? AppSessionStatus.authenticated
          : AppSessionStatus.onboardingRequired;
      notifyListeners();
    } on Object catch (error) {
      if (generation != _synchronizationGeneration) {
        return;
      }

      _errorMessage = _readableError(error);
      // A failed background refresh keeps the screen the user is on.
      if (!isRefresh) {
        _status = AppSessionStatus.failure;
      }
      notifyListeners();
    }
  }

  SupabaseClient _requireClient() {
    final client = _supabaseClient;
    if (client == null) {
      throw StateError('Supabase is not configured for this environment.');
    }
    return client;
  }

  String _readableError(Object error) {
    return readableAuthError(error) ??
        readableServerError(error) ??
        tr('Something went wrong. Please try again.');
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
