import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/beta_feedback.dart';

abstract interface class BetaFeedbackRepository {
  Future<List<BetaFeedback>> fetchMyFeedback();

  Future<BetaFeedback> submitFeedback(BetaFeedbackDraft draft);
}

class SupabaseBetaFeedbackRepository implements BetaFeedbackRepository {
  SupabaseBetaFeedbackRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<List<BetaFeedback>> fetchMyFeedback() async {
    final rows = await _client.rpc<List<dynamic>>('my_beta_feedback');
    return rows
        .map((row) => _fromMap(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  @override
  Future<BetaFeedback> submitFeedback(BetaFeedbackDraft draft) async {
    final result = await _client.rpc(
      'submit_beta_feedback',
      params: {
        'p_experience_area': draft.experienceArea.databaseValue,
        'p_safe_informed_score': draft.safeInformedScore,
        'p_comments': draft.comments,
      },
    );
    final feedback = await fetchMyFeedback();
    return feedback.firstWhere((entry) => entry.id == result as String);
  }

  BetaFeedback _fromMap(Map<String, dynamic> row) {
    return BetaFeedback(
      id: row['feedback_id'] as String,
      experienceArea: BetaExperienceArea.values.firstWhere(
        (area) => area.databaseValue == row['experience_area'] as String,
      ),
      safeInformedScore: row['safe_informed_score'] as int,
      comments: row['comments'] as String? ?? '',
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }
}

class PreviewBetaFeedbackRepository implements BetaFeedbackRepository {
  final List<BetaFeedback> _feedback = [];
  int _nextId = 1;

  @override
  Future<List<BetaFeedback>> fetchMyFeedback() async {
    return List.unmodifiable(_feedback);
  }

  @override
  Future<BetaFeedback> submitFeedback(BetaFeedbackDraft draft) async {
    final feedback = BetaFeedback(
      id: 'preview-beta-${_nextId++}',
      experienceArea: draft.experienceArea,
      safeInformedScore: draft.safeInformedScore,
      comments: draft.comments.trim(),
      createdAt: DateTime.now(),
    );
    _feedback.insert(0, feedback);
    return feedback;
  }
}
