import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../profile/domain/user_profile.dart';
import '../../trips/application/trip_catalog_controller.dart';
import '../../trips/domain/trip.dart';
import '../data/join_request_repository.dart';
import '../domain/trip_join_request.dart';

class JoinRequestController extends ChangeNotifier {
  JoinRequestController({
    required JoinRequestRepository repository,
    required String userId,
    required UserProfile profile,
    required TripCatalogController tripCatalog,
    Future<void> Function()? refreshChats,
    ProductAnalytics analytics = const NoopProductAnalytics(),
  }) : this._(
         repository,
         userId,
         profile,
         tripCatalog,
         refreshChats,
         analytics,
       );

  JoinRequestController._(
    this._repository,
    this._userId,
    this._profile,
    this._tripCatalog,
    this._refreshChats,
    this._analytics,
  );

  final JoinRequestRepository _repository;
  final String _userId;
  final UserProfile _profile;
  final TripCatalogController _tripCatalog;
  final Future<void> Function()? _refreshChats;
  final ProductAnalytics _analytics;

  List<TripJoinRequest> _travelerRequests = const [];
  List<TripJoinRequest> _hostRequests = const [];
  final Set<String> _updatingRequestIds = {};
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  List<TripJoinRequest> get travelerRequests =>
      List.unmodifiable(_travelerRequests);
  List<TripJoinRequest> get hostRequests => List.unmodifiable(_hostRequests);
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get errorMessage => _errorMessage;
  int get pendingHostReviewCount => _hostRequests
      .where((request) => request.status == JoinRequestStatus.pendingHost)
      .length;

  bool isUpdating(String requestId) {
    return _updatingRequestIds.contains(requestId);
  }

  TripJoinRequest? requestForTrip(String tripId) {
    for (final request in _travelerRequests) {
      if (request.tripId == tripId && request.status.isActive) {
        return request;
      }
    }
    return null;
  }

  List<TripJoinRequest> hostRequestsForTrip(String tripId) {
    return _hostRequests
        .where((request) => request.tripId == tripId)
        .toList(growable: false);
  }

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.fetchTravelerRequests(_userId),
        _repository.fetchHostRequests(_userId),
      ]);
      _travelerRequests = results[0];
      _hostRequests = results[1];
    } on Object catch (error) {
      _errorMessage = _readableError(error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<TripJoinRequest> submitRequest({
    required Trip trip,
    required String message,
  }) async {
    final trimmed = message.trim();
    if (trimmed.length < 20 || trimmed.length > 300) {
      throw ArgumentError('Write between 20 and 300 characters.');
    }

    _isSubmitting = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final request = await _repository.createRequest(
        trip: trip,
        traveler: _profile,
        message: trimmed,
      );
      _travelerRequests = [request, ..._travelerRequests];
      unawaited(
        _analytics.track(ProductEvent.joinRequestSubmitted, tripId: trip.id),
      );
      return request;
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> reviewAsHost(
    TripJoinRequest request, {
    required bool accept,
  }) async {
    await _updateRequest(
      request,
      () => _repository.reviewAsHost(requestId: request.id, accept: accept),
      updateHostList: true,
    );
  }

  Future<void> confirmAsTraveler(
    TripJoinRequest request, {
    required bool confirm,
  }) async {
    await _updateRequest(
      request,
      () => _repository.confirmAsTraveler(
        requestId: request.id,
        confirm: confirm,
      ),
      updateHostList: false,
    );
    if (confirm) {
      await _tripCatalog.load();
      await _refreshChats?.call();
      unawaited(
        _analytics.track(
          ProductEvent.tripPlaceConfirmed,
          tripId: request.tripId,
        ),
      );
      unawaited(
        _analytics.track(ProductEvent.groupCreated, tripId: request.tripId),
      );
    }
  }

  Future<void> withdraw(TripJoinRequest request) async {
    await _updateRequest(
      request,
      () => _repository.withdrawRequest(request.id),
      updateHostList: false,
    );
  }

  Future<void> _updateRequest(
    TripJoinRequest request,
    Future<TripJoinRequest> Function() operation, {
    required bool updateHostList,
  }) async {
    _updatingRequestIds.add(request.id);
    _errorMessage = null;
    notifyListeners();
    try {
      final updated = await operation();
      if (updateHostList) {
        _hostRequests = _replace(_hostRequests, updated);
      } else {
        _travelerRequests = _replace(_travelerRequests, updated);
      }
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _updatingRequestIds.remove(request.id);
      notifyListeners();
    }
  }

  List<TripJoinRequest> _replace(
    List<TripJoinRequest> source,
    TripJoinRequest updated,
  ) {
    return source
        .map((request) => request.id == updated.id ? updated : request)
        .toList(growable: false);
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
    return 'The request could not be updated. Please try again.';
  }
}
