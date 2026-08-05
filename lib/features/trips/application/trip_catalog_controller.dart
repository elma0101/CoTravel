import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../profile/domain/user_profile.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

class TripCatalogController extends ChangeNotifier {
  TripCatalogController({
    required TripRepository repository,
    required String userId,
    required UserProfile hostProfile,
    ProductAnalytics analytics = const NoopProductAnalytics(),
  }) : this._(repository, userId, hostProfile, analytics);

  TripCatalogController._(
    this._repository,
    this._userId,
    this._hostProfile,
    this._analytics,
  );

  final TripRepository _repository;
  final String _userId;
  final UserProfile _hostProfile;
  final ProductAnalytics _analytics;

  List<Trip> _discoverableTrips = const [];
  List<Trip> _hostedTrips = const [];
  TripFilter _filter = const TripFilter();
  Set<String> _blockedHostIds = const {};
  bool _isLoading = true;
  bool _isPublishing = false;
  String? _errorMessage;

  List<Trip> get discoverableTrips => _discoverableTrips
      .where((trip) => !_blockedHostIds.contains(trip.hostId))
      .where(_filter.matches)
      .toList(growable: false);
  List<Trip> get hostedTrips => List.unmodifiable(_hostedTrips);
  TripFilter get filter => _filter;
  bool get isLoading => _isLoading;
  bool get isPublishing => _isPublishing;
  String? get errorMessage => _errorMessage;

  Future<void> load() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _repository.discoverTrips(),
        _repository.fetchHostedTrips(_userId),
      ]);
      _discoverableTrips = results[0];
      _hostedTrips = results[1];
    } on Object {
      _errorMessage = 'Trips could not be loaded. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void applyFilter(TripFilter filter) {
    _filter = filter;
    notifyListeners();
  }

  void clearFilter() {
    _filter = const TripFilter();
    notifyListeners();
  }

  void setBlockedHosts(Set<String> hostIds) {
    if (setEquals(_blockedHostIds, hostIds)) {
      return;
    }
    _blockedHostIds = Set.unmodifiable(hostIds);
    notifyListeners();
  }

  Future<Trip> createTrip(TripDraft draft) async {
    _isPublishing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final trip = await _repository.createTrip(
        userId: _userId,
        hostProfile: _hostProfile,
        draft: draft,
      );
      _hostedTrips = [..._hostedTrips, trip]
        ..sort((left, right) => left.startDate.compareTo(right.startDate));
      _discoverableTrips = [..._discoverableTrips, trip]
        ..sort((left, right) => left.startDate.compareTo(right.startDate));
      unawaited(
        _analytics.track(
          ProductEvent.tripPublished,
          tripId: trip.id,
          properties: {
            'capacity': trip.capacity,
            'travel_style': trip.travelStyle,
          },
        ),
      );
      return trip;
    } on Object {
      _errorMessage = 'Your trip could not be published. Please try again.';
      rethrow;
    } finally {
      _isPublishing = false;
      notifyListeners();
    }
  }

  Future<Trip?> findTrip(String tripId) async {
    final loadedTrip = tripById(tripId);
    if (loadedTrip != null) {
      return loadedTrip;
    }
    final trip = await _repository.fetchTrip(tripId);
    if (trip != null &&
        trip.hostId != _userId &&
        _blockedHostIds.contains(trip.hostId)) {
      return null;
    }
    return trip;
  }

  Trip? tripById(String tripId) {
    for (final trip in _hostedTrips) {
      if (trip.id == tripId) {
        return trip;
      }
    }
    for (final trip in _discoverableTrips) {
      if (trip.id == tripId && !_blockedHostIds.contains(trip.hostId)) {
        return trip;
      }
    }
    return null;
  }
}
