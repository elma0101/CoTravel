class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.bio,
    required this.homeCity,
    required this.avatarUrl,
    required this.travelStyles,
    required this.languages,
    required this.isLinkedInVerified,
    required this.isOnboardingComplete,
  });

  const UserProfile.preview()
    : id = 'preview-user',
      displayName = 'Preview traveler',
      bio = 'Curious about new places and thoughtful group travel.',
      homeCity = 'Casablanca',
      avatarUrl = null,
      travelStyles = const ['Culture', 'Road trips'],
      languages = const ['Arabic', 'French', 'English'],
      isLinkedInVerified = true,
      isOnboardingComplete = true;

  const UserProfile.incompletePreview()
    : id = 'preview-user',
      displayName = null,
      bio = null,
      homeCity = null,
      avatarUrl = null,
      travelStyles = const [],
      languages = const [],
      isLinkedInVerified = true,
      isOnboardingComplete = false;

  final String id;
  final String? displayName;
  final String? bio;
  final String? homeCity;
  final String? avatarUrl;
  final List<String> travelStyles;
  final List<String> languages;
  final bool isLinkedInVerified;
  final bool isOnboardingComplete;

  String get initials {
    final parts = (displayName ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    final value = parts.map((part) => part[0].toUpperCase()).join();
    return value.isEmpty ? '?' : value;
  }
}

class ProfileDraft {
  const ProfileDraft({
    required this.displayName,
    required this.bio,
    required this.homeCity,
    required this.travelStyles,
    required this.languages,
  });

  final String displayName;
  final String bio;
  final String homeCity;
  final List<String> travelStyles;
  final List<String> languages;
}
