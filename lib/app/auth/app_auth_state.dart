import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics/product_analytics.dart';
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
    _status = AppSessionStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
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

  Future<void> signInForPreview() async {
    if (!previewAuthEnabled) {
      throw StateError('Preview authentication is disabled.');
    }

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

    _profile = null;
    _status = AppSessionStatus.signedOut;
    notifyListeners();
  }

  Future<void> _synchronizeSession(Session? session) async {
    final generation = ++_synchronizationGeneration;

    if (session == null) {
      _profile = null;
      _errorMessage = null;
      _status = AppSessionStatus.signedOut;
      notifyListeners();
      return;
    }

    _status = AppSessionStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final isVerified = await profileRepository.syncLinkedInVerification(
        session.user.id,
      );
      if (isVerified && !_hasTrackedVerifiedProfile) {
        _hasTrackedVerifiedProfile = true;
        unawaited(_analytics.track(ProductEvent.profileVerified));
      }
      final nextProfile = await profileRepository.fetchProfile(session.user.id);
      if (generation != _synchronizationGeneration) {
        return;
      }

      _profile = nextProfile;
      _status = nextProfile?.isOnboardingComplete == true
          ? AppSessionStatus.authenticated
          : AppSessionStatus.onboardingRequired;
      notifyListeners();
    } on Object catch (error) {
      if (generation != _synchronizationGeneration) {
        return;
      }

      _errorMessage = _readableError(error);
      _status = AppSessionStatus.failure;
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
    return switch (error) {
      AuthException(:final message) => message,
      PostgrestException(:final message) => message,
      StorageException(:final message) => message,
      _ => 'Something went wrong. Please try again.',
    };
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }
}
