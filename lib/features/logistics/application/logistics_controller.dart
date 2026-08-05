import 'package:flutter/foundation.dart';

import '../../trips/application/trip_catalog_controller.dart';
import '../../trips/domain/trip.dart';
import '../data/logistics_repository.dart';
import '../domain/trip_logistics.dart';

class LogisticsController extends ChangeNotifier {
  LogisticsController({
    required LogisticsRepository repository,
    required TripCatalogController tripCatalog,
  }) : this._(repository, tripCatalog);

  LogisticsController._(this._repository, this._tripCatalog);

  final LogisticsRepository _repository;
  final TripCatalogController _tripCatalog;
  final Map<String, TripLogistics> _plans = {};
  final Set<String> _loadingTripIds = {};
  final Set<String> _savingTripIds = {};
  String? _errorMessage;

  String? get errorMessage => _errorMessage;

  TripLogistics? planForTrip(String tripId) => _plans[tripId];

  bool isLoading(String tripId) => _loadingTripIds.contains(tripId);

  bool isSaving(String tripId) => _savingTripIds.contains(tripId);

  Future<TripLogistics> load(String tripId) async {
    final cached = _plans[tripId];
    if (cached != null) {
      return cached;
    }
    _loadingTripIds.add(tripId);
    _errorMessage = null;
    notifyListeners();
    try {
      final plan = await _repository.fetchForTrip(tripId);
      _plans[tripId] = plan;
      return plan;
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _loadingTripIds.remove(tripId);
      notifyListeners();
    }
  }

  Future<TripLogistics> save({
    required Trip trip,
    required LogisticsDraft draft,
  }) async {
    _savingTripIds.add(trip.id);
    _errorMessage = null;
    notifyListeners();
    try {
      final plan = await _repository.saveForTrip(trip: trip, draft: draft);
      _plans[trip.id] = plan;
      await _tripCatalog.load();
      return plan;
    } on Object catch (error) {
      _errorMessage = _readableError(error);
      rethrow;
    } finally {
      _savingTripIds.remove(trip.id);
      notifyListeners();
    }
  }

  String _readableError(Object error) {
    final message = error.toString();
    for (final prefix in ['Bad state: ', 'PostgrestException(message: ']) {
      if (message.startsWith(prefix)) {
        return message.substring(prefix.length).split(', code:').first;
      }
    }
    return 'Logistics could not be updated. Please try again.';
  }
}
