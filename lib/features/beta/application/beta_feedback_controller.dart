import 'package:flutter/foundation.dart';

import '../data/beta_feedback_repository.dart';
import '../domain/beta_feedback.dart';

class BetaFeedbackController extends ChangeNotifier {
  BetaFeedbackController(this._repository);

  final BetaFeedbackRepository _repository;

  List<BetaFeedback> _feedback = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<BetaFeedback> get feedback => List.unmodifiable(_feedback);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      _feedback = await _repository.fetchMyFeedback();
    } on Object catch (error) {
      _errorMessage = _readableError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<BetaFeedback> submit(BetaFeedbackDraft draft) async {
    if (draft.safeInformedScore < 1 || draft.safeInformedScore > 5) {
      throw ArgumentError('Choose a rating from 1 to 5.');
    }
    if (draft.comments.trim().length > 1000) {
      throw ArgumentError('Keep your note under 1000 characters.');
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final submitted = await _repository.submitFeedback(
        BetaFeedbackDraft(
          experienceArea: draft.experienceArea,
          safeInformedScore: draft.safeInformedScore,
          comments: draft.comments.trim(),
        ),
      );
      _feedback = [
        submitted,
        ..._feedback.where((entry) => entry.id != submitted.id),
      ];
      return submitted;
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  String _readableError(Object error) {
    final message = error.toString();
    for (final prefix in [
      'Bad state: ',
      'Invalid argument(s): ',
      'PostgrestException(message: ',
    ]) {
      if (message.startsWith(prefix)) {
        return message.substring(prefix.length).split(', code:').first;
      }
    }
    return 'Your feedback could not be sent. Please try again.';
  }
}
