import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/safety_models.dart';

abstract interface class SafetyRepository {
  Future<List<SafetyReport>> fetchMyReports();

  Future<List<BlockedUser>> fetchBlockedUsers();

  Future<SafetyReport> submitReport({
    required SafetyTarget target,
    required SafetyReportReason reason,
    required String details,
  });

  Future<BlockedUser> blockUser(SafetyTarget target);

  Future<void> unblockUser(String userId);
}

class SupabaseSafetyRepository implements SafetyRepository {
  SupabaseSafetyRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<SafetyReport>> fetchMyReports() async {
    final rows = await _client.rpc<List<dynamic>>('my_safety_reports');
    return rows
        .map((row) => _reportFromMap(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    final rows = await _client.rpc<List<dynamic>>('my_blocked_users');
    return rows
        .map((row) => _blockedUserFromMap(row as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<SafetyReport> submitReport({
    required SafetyTarget target,
    required SafetyReportReason reason,
    required String details,
  }) async {
    final result = await _client.rpc(
      'submit_safety_report',
      params: {
        'p_subject_user_id': target.userId,
        'p_trip_id': target.tripId,
        'p_reason': reason.databaseValue,
        'p_details': details,
      },
    );
    final reports = await fetchMyReports();
    return reports.firstWhere((report) => report.id == result as String);
  }

  @override
  Future<BlockedUser> blockUser(SafetyTarget target) async {
    await _client.rpc(
      'block_user',
      params: {'p_blocked_user_id': target.userId},
    );
    final blockedUsers = await fetchBlockedUsers();
    return blockedUsers.firstWhere((user) => user.userId == target.userId);
  }

  @override
  Future<void> unblockUser(String userId) async {
    await _client.rpc('unblock_user', params: {'p_blocked_user_id': userId});
  }

  SafetyReport _reportFromMap(Map<String, dynamic> row) {
    return SafetyReport(
      id: row['report_id'] as String,
      subjectUserId: row['subject_user_id'] as String,
      subjectName: row['subject_name'] as String? ?? 'CoTravel member',
      tripId: row['trip_id'] as String?,
      tripTitle: row['trip_title'] as String?,
      reason: _reason(row['reason'] as String),
      details: row['details'] as String,
      status: _status(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  BlockedUser _blockedUserFromMap(Map<String, dynamic> row) {
    return BlockedUser(
      userId: row['blocked_user_id'] as String,
      displayName: row['display_name'] as String? ?? 'CoTravel member',
      blockedAt: DateTime.parse(row['blocked_at'] as String),
    );
  }

  SafetyReportReason _reason(String value) {
    return SafetyReportReason.values.firstWhere(
      (reason) => reason.databaseValue == value,
    );
  }

  SafetyReportStatus _status(String value) {
    return SafetyReportStatus.values.firstWhere(
      (status) => status.databaseValue == value,
    );
  }
}

class PreviewSafetyRepository implements SafetyRepository {
  final List<SafetyReport> _reports = [];
  final List<BlockedUser> _blockedUsers = [];
  int _nextReportId = 1;

  @override
  Future<List<SafetyReport>> fetchMyReports() async {
    return List.unmodifiable(_reports);
  }

  @override
  Future<List<BlockedUser>> fetchBlockedUsers() async {
    return List.unmodifiable(_blockedUsers);
  }

  @override
  Future<SafetyReport> submitReport({
    required SafetyTarget target,
    required SafetyReportReason reason,
    required String details,
  }) async {
    if (target.userId == 'preview-user') {
      throw StateError('You cannot report your own profile.');
    }
    final report = SafetyReport(
      id: 'preview-report-${_nextReportId++}',
      subjectUserId: target.userId,
      subjectName: target.userName,
      tripId: target.tripId,
      tripTitle: target.tripTitle,
      reason: reason,
      details: details.trim(),
      status: SafetyReportStatus.submitted,
      createdAt: DateTime.now(),
    );
    _reports.insert(0, report);
    return report;
  }

  @override
  Future<BlockedUser> blockUser(SafetyTarget target) async {
    if (target.userId == 'preview-user') {
      throw StateError('You cannot block your own profile.');
    }
    final existing = _blockedUsers.where(
      (user) => user.userId == target.userId,
    );
    if (existing.isNotEmpty) {
      return existing.first;
    }
    final user = BlockedUser(
      userId: target.userId,
      displayName: target.userName,
      blockedAt: DateTime.now(),
    );
    _blockedUsers.insert(0, user);
    return user;
  }

  @override
  Future<void> unblockUser(String userId) async {
    _blockedUsers.removeWhere((user) => user.userId == userId);
  }
}
