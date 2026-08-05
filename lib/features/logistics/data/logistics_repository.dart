import 'package:supabase_flutter/supabase_flutter.dart';

import '../../trips/data/trip_repository.dart';
import '../../trips/domain/trip.dart';
import '../domain/trip_logistics.dart';

abstract interface class LogisticsRepository {
  Future<TripLogistics> fetchForTrip(String tripId);

  Future<TripLogistics> saveForTrip({
    required Trip trip,
    required LogisticsDraft draft,
  });
}

class SupabaseLogisticsRepository implements LogisticsRepository {
  SupabaseLogisticsRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<TripLogistics> fetchForTrip(String tripId) async {
    final row = await _client
        .from('trip_logistics')
        .select()
        .eq('trip_id', tripId)
        .maybeSingle();
    return row == null ? TripLogistics(tripId: tripId) : _fromMap(row);
  }

  @override
  Future<TripLogistics> saveForTrip({
    required Trip trip,
    required LogisticsDraft draft,
  }) async {
    await _client.rpc(
      'save_trip_logistics',
      params: {
        'p_trip_id': trip.id,
        'p_lodging_total': draft.lodgingTotal,
        'p_transport_total': draft.transportTotal,
        'p_accommodation_name': draft.accommodationName,
        'p_accommodation_url': draft.accommodationUrl?.toString(),
        'p_transport_name': draft.transportName,
        'p_transport_url': draft.transportUrl?.toString(),
        'p_notes': draft.notes,
      },
    );
    return fetchForTrip(trip.id);
  }

  TripLogistics _fromMap(Map<String, dynamic> row) {
    return TripLogistics(
      tripId: row['trip_id'] as String,
      accommodationName: row['accommodation_name'] as String?,
      accommodationUrl: _readUri(row['accommodation_url']),
      transportName: row['transport_name'] as String?,
      transportUrl: _readUri(row['transport_url']),
      notes: row['notes'] as String?,
      updatedAt: row['updated_at'] == null
          ? null
          : DateTime.parse(row['updated_at'] as String),
    );
  }

  Uri? _readUri(Object? value) {
    final raw = value as String?;
    return raw == null ? null : Uri.tryParse(raw);
  }
}

class PreviewLogisticsRepository implements LogisticsRepository {
  PreviewLogisticsRepository({required PreviewTripRepository tripRepository})
    : this._(tripRepository);

  PreviewLogisticsRepository._(this._tripRepository)
    : _plans = {
        'dades-slow-road': TripLogistics(
          tripId: 'dades-slow-road',
          accommodationName: 'Dades guesthouse shortlist',
          accommodationUrl: Uri.parse('https://www.airbnb.com/'),
          transportName: 'inDrive intercity',
          transportUrl: Uri.parse('https://indrive.com/'),
          notes:
              'Leila will confirm the guesthouse after the group compares the shortlist in chat.',
        ),
      };

  final PreviewTripRepository _tripRepository;
  final Map<String, TripLogistics> _plans;

  @override
  Future<TripLogistics> fetchForTrip(String tripId) async {
    return _plans[tripId] ?? TripLogistics(tripId: tripId);
  }

  @override
  Future<TripLogistics> saveForTrip({
    required Trip trip,
    required LogisticsDraft draft,
  }) async {
    if (trip.hostId != 'preview-user') {
      throw StateError('Only this trip host can update logistics.');
    }
    await _tripRepository.updateCostEstimates(
      tripId: trip.id,
      lodgingTotal: draft.lodgingTotal,
      transportTotal: draft.transportTotal,
    );
    final plan = TripLogistics(
      tripId: trip.id,
      accommodationName: draft.accommodationName,
      accommodationUrl: draft.accommodationUrl,
      transportName: draft.transportName,
      transportUrl: draft.transportUrl,
      notes: draft.notes,
      updatedAt: DateTime.now(),
    );
    _plans[trip.id] = plan;
    return plan;
  }
}
