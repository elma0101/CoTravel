enum SafetyReportReason {
  harassment('Harassment or intimidation', 'harassment'),
  suspiciousProfile('Suspicious or misleading profile', 'suspicious_profile'),
  unsafePlan('Unsafe trip plan', 'unsafe_plan'),
  spam('Spam or commercial solicitation', 'spam'),
  other('Something else', 'other');

  const SafetyReportReason(this.label, this.databaseValue);

  final String label;
  final String databaseValue;
}

enum SafetyReportStatus {
  submitted('Submitted', 'submitted'),
  inReview('In review', 'in_review'),
  resolved('Resolved', 'resolved'),
  dismissed('Closed', 'dismissed');

  const SafetyReportStatus(this.label, this.databaseValue);

  final String label;
  final String databaseValue;
}

class SafetyTarget {
  const SafetyTarget({
    required this.userId,
    required this.userName,
    this.tripId,
    this.tripTitle,
  });

  final String userId;
  final String userName;
  final String? tripId;
  final String? tripTitle;
}

class SafetyReport {
  const SafetyReport({
    required this.id,
    required this.subjectUserId,
    required this.subjectName,
    required this.reason,
    required this.details,
    required this.status,
    required this.createdAt,
    this.tripId,
    this.tripTitle,
  });

  final String id;
  final String subjectUserId;
  final String subjectName;
  final String? tripId;
  final String? tripTitle;
  final SafetyReportReason reason;
  final String details;
  final SafetyReportStatus status;
  final DateTime createdAt;
}

class BlockedUser {
  const BlockedUser({
    required this.userId,
    required this.displayName,
    required this.blockedAt,
  });

  final String userId;
  final String displayName;
  final DateTime blockedAt;
}
