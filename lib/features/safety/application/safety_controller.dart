import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../trips/application/trip_catalog_controller.dart';
import '../data/safety_repository.dart';
import '../domain/safety_models.dart';

class SafetyController extends ChangeNotifier {
  SafetyController({
    required SafetyRepository repository,
    required TripCatalogController tripCatalog,
    ProductAnalytics analytics = const NoopProductAnalytics(),
  }) : this._(repository, tripCatalog, analytics);

  SafetyController._(this._repository, this._tripCatalog, this._analytics);

  final SafetyRepository _repository;
  final TripCatalogController _tripCatalog;
  final ProductAnalytics _analytics;

  List<SafetyReport> _reports = const [];
  List<BlockedUser> _blockedUsers = const [];
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<SafetyReport> get reports => List.unmodifiable(_reports);
  List<BlockedUser> get blockedUsers => List.unmodifiable(_blockedUsers);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;

  bool isBlocked(String? userId) {
    return userId != null && _blockedUsers.any((user) => user.userId == userId);
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.fetchMyReports(),
        _repository.fetchBlockedUsers(),
      ]);
      _reports = results[0] as List<SafetyReport>;
      _blockedUsers = results[1] as List<BlockedUser>;
      _synchronizeBlockedHosts();
    } on Object catch (error) {
      _errorMessage = _readableError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<SafetyReport> submitReport({
    required SafetyTarget target,
    required SafetyReportReason reason,
    required String details,
  }) async {
    final trimmed = details.trim();
    if (trimmed.length < 10 || trimmed.length > 1000) {
      throw ArgumentError('Add between 10 and 1000 characters.');
    }
    return _runSubmission(() async {
      final report = await _repository.submitReport(
        target: target,
        reason: reason,
        details: trimmed,
      );
      _reports = [report, ..._reports];
      unawaited(
        _analytics.track(
          ProductEvent.safetyReportSubmitted,
          tripId: target.tripId,
          properties: {'reason': reason.databaseValue},
        ),
      );
      return report;
    });
  }

  Future<void> block(SafetyTarget target) async {
    await _runSubmission(() async {
      final blocked = await _repository.blockUser(target);
      _blockedUsers = [
        blocked,
        ..._blockedUsers.where((user) => user.userId != blocked.userId),
      ];
      _synchronizeBlockedHosts();
      unawaited(_analytics.track(ProductEvent.userBlocked));
    });
  }

  Future<void> unblock(String userId) async {
    await _runSubmission(() async {
      await _repository.unblockUser(userId);
      _blockedUsers = _blockedUsers
          .where((user) => user.userId != userId)
          .toList(growable: false);
      _synchronizeBlockedHosts();
    });
  }

  Future<T> _runSubmission<T>(Future<T> Function() operation) async {
    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      return await operation();
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  void _synchronizeBlockedHosts() {
    _tripCatalog.setBlockedHosts(
      _blockedUsers.map((user) => user.userId).toSet(),
    );
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
    return 'The safety action could not be completed. Please try again.';
  }
}
