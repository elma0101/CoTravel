import '../../../core/l10n/app_strings.dart';

enum BetaExperienceArea {
  discovery,
  joining,
  hosting,
  coordination;

  String get databaseValue => name;

  String get label => switch (this) {
    discovery => tr('Finding a trip'),
    joining => tr('Joining a group'),
    hosting => tr('Hosting a trip'),
    coordination => tr('Planning together'),
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
