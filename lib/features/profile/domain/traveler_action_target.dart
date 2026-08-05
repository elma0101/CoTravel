import 'user_profile.dart';

class TravelerActionTarget {
  const TravelerActionTarget({
    required this.userId,
    required this.displayName,
    this.homeCity,
    this.avatarUrl,
    this.isVerified = false,
    this.tripId,
    this.tripTitle,
    this.conversationId,
  });

  factory TravelerActionTarget.fromProfile(
    UserProfile profile, {
    String? tripId,
    String? tripTitle,
    String? conversationId,
  }) {
    return TravelerActionTarget(
      userId: profile.id,
      displayName: profile.displayName ?? 'CoTravel member',
      homeCity: profile.homeCity,
      avatarUrl: profile.avatarUrl,
      isVerified: profile.isLinkedInVerified,
      tripId: tripId,
      tripTitle: tripTitle,
      conversationId: conversationId,
    );
  }

  final String userId;
  final String displayName;
  final String? homeCity;
  final String? avatarUrl;
  final bool isVerified;
  final String? tripId;
  final String? tripTitle;
  final String? conversationId;

  String get initials {
    final value = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
    return value.isEmpty ? '?' : value;
  }
}
