enum BetaExperienceArea {
  discovery,
  joining,
  hosting,
  coordination;

  String get databaseValue => name;

  String get label => switch (this) {
    discovery => 'Finding a trip',
    joining => 'Joining a group',
    hosting => 'Hosting a trip',
    coordination => 'Planning together',
  };
}

class BetaFeedbackDraft {
  const BetaFeedbackDraft({
    required this.experienceArea,
    required this.safeInformedScore,
    required this.comments,
  });

  final BetaExperienceArea experienceArea;
  final int safeInformedScore;
  final String comments;
}

class BetaFeedback {
  const BetaFeedback({
    required this.id,
    required this.experienceArea,
    required this.safeInformedScore,
    required this.comments,
    required this.createdAt,
  });

  final String id;
  final BetaExperienceArea experienceArea;
  final int safeInformedScore;
  final String comments;
  final DateTime createdAt;

  bool get isPositive => safeInformedScore >= 4;
}
