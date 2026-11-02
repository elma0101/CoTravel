import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/analytics/product_analytics.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/state/dispose_safe_notifier.dart';
import '../../profile/domain/user_profile.dart';
import '../data/trip_repository.dart';
import '../domain/trip.dart';

class TripCatalogController extends ChangeNotifier with DisposeSafeNotifier {
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
  List<Trip> _savedTrips = const [];
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
  List<Trip> get savedTrips => _savedTrips
      .where((trip) => !_blockedHostIds.contains(trip.hostId))
      .toList(growable: false);
  bool isSaved(String tripId) => _savedTrips.any((trip) => trip.id == tripId);
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
        _repository.fetchSavedTrips(_userId),
      ]);
      _discoverableTrips = results[0];
      _hostedTrips = results[1];
      _savedTrips = results[2];
    } on Object {
      _errorMessage = tr('Trips could not be loaded. Please try again.');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Updates the list first so the bookmark responds at once, and restores it
  /// if the server refuses.
  Future<void> toggleSaved(Trip trip) async {
    final previous = _savedTrips;
    final wasSaved = isSaved(trip.id);
    _savedTrips = wasSaved
        ? previous.where((item) => item.id != trip.id).toList(growable: false)
        : ([...previous, trip]
            ..sort((left, right) => left.startDate.compareTo(right.startDate)));
    notifyListeners();
    try {
      if (wasSaved) {
        await _repository.unsaveTrip(userId: _userId, tripId: trip.id);
      } else {
        await _repository.saveTrip(userId: _userId, tripId: trip.id);
      }
    } on Object {
      _savedTrips = previous;
      notifyListeners();
      rethrow;
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
      _errorMessage = tr('Your trip could not be published. Please try again.');
      rethrow;
    } finally {
      _isPublishing = false;
      notifyListeners();
    }
  }

  Future<Trip> updateTrip(String tripId, TripDraft draft) async {
    _isPublishing = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await _repository.updateTrip(
        tripId: tripId,
        draft: draft,
      );
      _hostedTrips = _replaced(_hostedTrips, updated);
      _discoverableTrips = _replaced(_discoverableTrips, updated);
      _savedTrips = _replaced(_savedTrips, updated);
      return updated;
    } on Object {
      _errorMessage = tr('Your changes could not be saved. Please try again.');
      rethrow;
    } finally {
      _isPublishing = false;
      notifyListeners();
    }
  }

  /// Saves the host's photo choices. Separate from publishing, so a trip
  /// still exists when only its photos fail.
  Future<Trip> saveTripPhotos(
    Trip trip, {
    required List<TripPhoto> kept,
    required List<NewTripPhoto> added,
  }) async {
    final updated = await _repository.saveTripPhotos(
      trip: trip,
      kept: kept,
      added: added,
    );
    _hostedTrips = _replaced(_hostedTrips, updated);
    _discoverableTrips = _replaced(_discoverableTrips, updated);
    _savedTrips = _replaced(_savedTrips, updated);
    notifyListeners();
    return updated;
  }

  Future<void> cancelTrip(Trip trip) async {
    await _repository.cancelTrip(trip.id);
    _hostedTrips = _replaced(
      _hostedTrips,
      trip.copyWith(status: TripStatus.cancelled),
    );
    _discoverableTrips = _discoverableTrips
        .where((item) => item.id != trip.id)
        .toList(growable: false);
    notifyListeners();
  }

  List<Trip> _replaced(List<Trip> trips, Trip updated) {
    return trips.map((trip) => trip.id == updated.id ? updated : trip).toList()
      ..sort((left, right) => left.startDate.compareTo(right.startDate));
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
