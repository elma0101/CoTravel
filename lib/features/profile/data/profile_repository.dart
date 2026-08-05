import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile?> fetchProfile(String userId);

  Future<UserProfile> completeProfile({
    required String userId,
    required ProfileDraft draft,
    Uint8List? avatarBytes,
    String avatarExtension,
  });

  Future<bool> syncLinkedInVerification(String userId);
}

class SupabaseProfileRepository implements ProfileRepository {
  SupabaseProfileRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<UserProfile?> fetchProfile(String userId) async {
    final data = await _client
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) {
      return null;
    }

    return _fromMap(data);
  }

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required ProfileDraft draft,
    Uint8List? avatarBytes,
    String avatarExtension = 'jpg',
  }) async {
    String? avatarPath;

    if (avatarBytes != null) {
      final normalizedExtension = _normalizeExtension(avatarExtension);
      avatarPath = '$userId/avatar.$normalizedExtension';
      await _client.storage
          .from('avatars')
          .uploadBinary(
            avatarPath,
            avatarBytes,
            fileOptions: FileOptions(
              upsert: true,
              contentType: _contentType(normalizedExtension),
            ),
          );
    }

    await _client.rpc(
      'complete_profile',
      params: {
        'p_display_name': draft.displayName,
        'p_bio': draft.bio,
        'p_home_city': draft.homeCity,
        'p_travel_styles': draft.travelStyles,
        'p_languages': draft.languages,
        'p_avatar_path': avatarPath,
      },
    );

    final profile = await fetchProfile(userId);
    if (profile == null) {
      throw StateError('Profile was not available after saving.');
    }
    return profile;
  }

  @override
  Future<bool> syncLinkedInVerification(String userId) async {
    final result = await _client.rpc<bool>('sync_my_linkedin_verification');
    return result;
  }

  UserProfile _fromMap(Map<String, dynamic> data) {
    final avatarPath = data['avatar_path'] as String?;

    return UserProfile(
      id: data['id'] as String,
      displayName: data['display_name'] as String?,
      bio: data['bio'] as String?,
      homeCity: data['home_city'] as String?,
      avatarUrl: avatarPath == null
          ? null
          : _client.storage.from('avatars').getPublicUrl(avatarPath),
      travelStyles: List<String>.from(
        data['travel_styles'] as List? ?? const [],
      ),
      languages: List<String>.from(data['languages'] as List? ?? const []),
      isLinkedInVerified: data['linkedin_verified_at'] != null,
      isOnboardingComplete: data['onboarding_completed_at'] != null,
    );
  }

  String _normalizeExtension(String value) {
    return switch (value.toLowerCase()) {
      'png' => 'png',
      'webp' => 'webp',
      _ => 'jpg',
    };
  }

  String _contentType(String extension) {
    return switch (extension) {
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}

class PreviewProfileRepository implements ProfileRepository {
  UserProfile _profile = const UserProfile.preview();

  @override
  Future<UserProfile?> fetchProfile(String userId) async => _profile;

  @override
  Future<UserProfile> completeProfile({
    required String userId,
    required ProfileDraft draft,
    Uint8List? avatarBytes,
    String avatarExtension = 'jpg',
  }) async {
    _profile = UserProfile(
      id: userId,
      displayName: draft.displayName,
      bio: draft.bio,
      homeCity: draft.homeCity,
      avatarUrl: null,
      travelStyles: draft.travelStyles,
      languages: draft.languages,
      isLinkedInVerified: true,
      isOnboardingComplete: true,
    );
    return _profile;
  }

  @override
  Future<bool> syncLinkedInVerification(String userId) async => true;
}
