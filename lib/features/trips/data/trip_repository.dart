import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/user_profile.dart';
import '../domain/trip.dart';
import '../domain/trip_route.dart';

abstract interface class TripRepository {
  Future<List<Trip>> discoverTrips();

  Future<List<Trip>> fetchHostedTrips(String userId);

  Future<Trip?> fetchTrip(String tripId);

  Future<Trip> createTrip({
    required String userId,
    required UserProfile hostProfile,
    required TripDraft draft,
  });
}

class SupabaseTripRepository implements TripRepository {
  SupabaseTripRepository(this._client);

  static const _tripSelection = '''
    *,
    trip_stops(
      city,
      arrival_date,
      notes,
      position,
      latitude,
      longitude,
      stop_type,
      travel_mode,
      travel_duration_minutes,
      is_optional
    ),
    host:profiles!trips_host_id_fkey(
      display_name,
      home_city,
      linkedin_verified_at
    )
  ''';

  final SupabaseClient _client;

  @override
  Future<List<Trip>> discoverTrips() async {
    final rows = await _client
        .from('trips')
        .select(_tripSelection)
        .eq('status', 'published')
        .gt('open_seats', 0)
        .order('start_date');
    return rows.map(_fromMap).toList();
  }

  @override
  Future<List<Trip>> fetchHostedTrips(String userId) async {
    final rows = await _client
        .from('trips')
        .select(_tripSelection)
        .eq('host_id', userId)
        .order('start_date');
    return rows.map(_fromMap).toList();
  }

  @override
  Future<Trip?> fetchTrip(String tripId) async {
    final row = await _client
        .from('trips')
        .select(_tripSelection)
        .eq('id', tripId)
        .maybeSingle();
    return row == null ? null : _fromMap(row);
  }

  @override
  Future<Trip> createTrip({
    required String userId,
    required UserProfile hostProfile,
    required TripDraft draft,
  }) async {
    final result = await _client.rpc(
      'create_trip',
      params: {
        'p_title': draft.title,
        'p_origin_city': draft.originCity,
        'p_start_date': _dateValue(draft.startDate),
        'p_end_date': _dateValue(draft.endDate),
        'p_stops': draft.stops.map((stop) {
          final resolved = MoroccoRouteCoordinates.resolve(stop);
          return {
            'city': resolved.city,
            'arrival_date': _dateValue(resolved.arrivalDate),
            'notes': resolved.notes,
            'latitude': resolved.latitude,
            'longitude': resolved.longitude,
            'stop_type': resolved.type.storageValue,
            'travel_mode': resolved.travelMode?.storageValue,
            'travel_duration_minutes': resolved.travelDurationMinutes,
            'is_optional': resolved.isOptional,
          };
        }).toList(),
        'p_capacity': draft.capacity,
        'p_lodging_total': draft.lodgingTotal,
        'p_transport_total': draft.transportTotal,
        'p_currency': draft.currency,
        'p_travel_style': draft.travelStyle,
        'p_summary': draft.summary,
      },
    );

    final trip = await fetchTrip(result as String);
    if (trip == null) {
      throw StateError('Trip was not available after publishing.');
    }
    return trip;
  }

  Trip _fromMap(Map<String, dynamic> row) {
    final rawStops =
        List<Map<String, dynamic>>.from(row['trip_stops'] as List? ?? const [])
          ..sort(
            (left, right) =>
                (left['position'] as num).compareTo(right['position'] as num),
          );
    final host = row['host'] as Map<String, dynamic>? ?? const {};

    return Trip(
      id: row['id'] as String,
      hostId: row['host_id'] as String,
      hostName: host['display_name'] as String? ?? 'CoTravel host',
      hostHomeCity: host['home_city'] as String?,
      hostVerified: host['linkedin_verified_at'] != null,
      title: row['title'] as String,
      originCity: row['origin_city'] as String,
      startDate: DateTime.parse(row['start_date'] as String),
      endDate: DateTime.parse(row['end_date'] as String),
      stops: rawStops
          .map(
            (stop) => TripStop(
              city: stop['city'] as String,
              arrivalDate: DateTime.parse(stop['arrival_date'] as String),
              notes: stop['notes'] as String?,
              latitude: (stop['latitude'] as num?)?.toDouble(),
              longitude: (stop['longitude'] as num?)?.toDouble(),
              type: TripStopTypeValue.fromStorage(stop['stop_type'] as String?),
              travelMode: TripTravelModeValue.fromStorage(
                stop['travel_mode'] as String?,
              ),
              travelDurationMinutes: (stop['travel_duration_minutes'] as num?)
                  ?.toInt(),
              isOptional: stop['is_optional'] as bool? ?? false,
            ),
          )
          .toList(),
      capacity: row['capacity'] as int,
      confirmedTravelerCount: row['confirmed_traveler_count'] as int,
      lodgingTotal: (row['lodging_total'] as num).toDouble(),
      transportTotal: (row['transport_total'] as num).toDouble(),
      currency: row['currency'] as String,
      travelStyle: row['travel_style'] as String,
      summary: row['summary'] as String,
    );
  }

  String _dateValue(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class PreviewTripRepository implements TripRepository {
  PreviewTripRepository({DateTime? today})
    : _trips = _seedTrips(today ?? DateTime.now());

  final List<Trip> _trips;
  int _nextId = 1;

  Future<Trip> updateCostEstimates({
    required String tripId,
    required double lodgingTotal,
    required double transportTotal,
  }) async {
    final index = _trips.indexWhere((trip) => trip.id == tripId);
    if (index == -1) {
      throw StateError('Trip not found.');
    }
    final updated = _trips[index].copyWith(
      lodgingTotal: lodgingTotal,
      transportTotal: transportTotal,
    );
    _trips[index] = updated;
    return updated;
  }

  Future<void> confirmTraveler(String tripId) async {
    final index = _trips.indexWhere((trip) => trip.id == tripId);
    if (index == -1) {
      throw StateError('Trip not found.');
    }
    final trip = _trips[index];
    if (trip.openSeats <= 0) {
      throw StateError('This trip no longer has an open seat.');
    }
    _trips[index] = trip.copyWith(
      confirmedTravelerCount: trip.confirmedTravelerCount + 1,
    );
  }

  @override
  Future<List<Trip>> discoverTrips() async {
    return _trips.where((trip) => trip.openSeats > 0).toList()
      ..sort((left, right) => left.startDate.compareTo(right.startDate));
  }

  @override
  Future<List<Trip>> fetchHostedTrips(String userId) async {
    return _trips.where((trip) => trip.hostId == userId).toList()
      ..sort((left, right) => left.startDate.compareTo(right.startDate));
  }

  @override
  Future<Trip?> fetchTrip(String tripId) async {
    for (final trip in _trips) {
      if (trip.id == tripId) {
        return trip;
      }
    }
    return null;
  }

  @override
  Future<Trip> createTrip({
    required String userId,
    required UserProfile hostProfile,
    required TripDraft draft,
  }) async {
    final trip = Trip(
      id: 'preview-created-${_nextId++}',
      hostId: userId,
      hostName: hostProfile.displayName ?? 'Preview traveler',
      hostHomeCity: hostProfile.homeCity,
      hostVerified: hostProfile.isLinkedInVerified,
      title: draft.title,
      originCity: draft.originCity,
      startDate: draft.startDate,
      endDate: draft.endDate,
      stops: draft.stops.map(MoroccoRouteCoordinates.resolve).toList(),
      capacity: draft.capacity,
      confirmedTravelerCount: 0,
      lodgingTotal: draft.lodgingTotal,
      transportTotal: draft.transportTotal,
      currency: draft.currency,
      travelStyle: draft.travelStyle,
      summary: draft.summary,
    );
    _trips.add(trip);
    return trip;
  }

  static List<Trip> _seedTrips(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final atlasStart = today.add(const Duration(days: 17));
    final rifStart = today.add(const Duration(days: 24));
    final coastStart = today.add(const Duration(days: 31));
    final dadesStart = today.add(const Duration(days: 38));
    final northStart = today.add(const Duration(days: 46));

    return [
      Trip(
        id: 'atlas-weekend',
        hostId: 'host-amina',
        hostName: 'Amina B.',
        hostHomeCity: 'Casablanca',
        hostVerified: true,
        title: 'Atlas villages weekend',
        originCity: 'Casablanca',
        startDate: atlasStart,
        endDate: atlasStart.add(const Duration(days: 3)),
        stops: [
          TripStop(
            city: 'Marrakech',
            arrivalDate: atlasStart,
            type: TripStopType.activity,
            travelMode: TripTravelMode.train,
            travelDurationMinutes: 160,
            notes: 'Meet near the medina for a relaxed first evening.',
          ),
          TripStop(
            city: 'Imlil',
            arrivalDate: atlasStart.add(const Duration(days: 1)),
            type: TripStopType.overnight,
            travelMode: TripTravelMode.sharedTaxi,
            travelDurationMinutes: 90,
            notes: 'Easy mountain walks and a village guesthouse.',
          ),
        ],
        capacity: 5,
        confirmedTravelerCount: 1,
        lodgingTotal: 3600,
        transportTotal: 1400,
        currency: 'MAD',
        travelStyle: 'Nature',
        summary:
            'A relaxed long weekend between Marrakech and the High Atlas, with unhurried walks and shared local meals.',
      ),
      Trip(
        id: 'preview-rif-loop',
        hostId: 'preview-user',
        hostName: 'Preview traveler',
        hostHomeCity: 'Casablanca',
        hostVerified: true,
        title: 'Rif towns and trails',
        originCity: 'Casablanca',
        startDate: rifStart,
        endDate: rifStart.add(const Duration(days: 4)),
        stops: [
          TripStop(
            city: 'Tetouan',
            arrivalDate: rifStart,
            type: TripStopType.activity,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 300,
          ),
          TripStop(
            city: 'Akchour',
            arrivalDate: rifStart.add(const Duration(days: 2)),
            type: TripStopType.activity,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 75,
            notes: 'A moderate trail day with an early start.',
          ),
          TripStop(
            city: 'Chefchaouen',
            arrivalDate: rifStart.add(const Duration(days: 3)),
            type: TripStopType.overnight,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 45,
          ),
        ],
        capacity: 4,
        confirmedTravelerCount: 0,
        lodgingTotal: 3600,
        transportTotal: 1600,
        currency: 'MAD',
        travelStyle: 'Nature',
        summary:
            'A small northern loop balancing old towns, one trail day, and plenty of time to slow down.',
      ),
      Trip(
        id: 'essaouira-coast',
        hostId: 'host-youssef',
        hostName: 'Youssef E.',
        hostHomeCity: 'Rabat',
        hostVerified: true,
        title: 'Coast, food, and surf',
        originCity: 'Rabat',
        startDate: coastStart,
        endDate: coastStart.add(const Duration(days: 4)),
        stops: [
          TripStop(
            city: 'El Jadida',
            arrivalDate: coastStart,
            type: TripStopType.activity,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 110,
          ),
          TripStop(
            city: 'Essaouira',
            arrivalDate: coastStart.add(const Duration(days: 2)),
            type: TripStopType.overnight,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 230,
          ),
        ],
        capacity: 4,
        confirmedTravelerCount: 0,
        lodgingTotal: 4200,
        transportTotal: 1800,
        currency: 'MAD',
        travelStyle: 'Food',
        summary:
            'A small road trip for people who like coastal towns, seafood markets, and one beginner-friendly surf morning.',
      ),
      Trip(
        id: 'dades-slow-road',
        hostId: 'host-leila',
        hostName: 'Leila M.',
        hostHomeCity: 'Marrakech',
        hostVerified: true,
        title: 'Dades slow road',
        originCity: 'Marrakech',
        startDate: dadesStart,
        endDate: dadesStart.add(const Duration(days: 4)),
        stops: [
          TripStop(
            city: 'Ait Ben Haddou',
            arrivalDate: dadesStart,
            type: TripStopType.activity,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 210,
            notes: 'Walk through the ksar before the afternoon heat.',
          ),
          TripStop(
            city: 'Skoura',
            arrivalDate: dadesStart.add(const Duration(days: 1)),
            type: TripStopType.overnight,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 75,
            notes: 'Palm-grove guesthouse and a flexible afternoon.',
          ),
          TripStop(
            city: 'Boumalne Dades',
            arrivalDate: dadesStart.add(const Duration(days: 2)),
            type: TripStopType.activity,
            travelMode: TripTravelMode.drive,
            travelDurationMinutes: 105,
            notes: 'Explore the gorge viewpoints at an easy pace.',
          ),
        ],
        capacity: 5,
        confirmedTravelerCount: 2,
        lodgingTotal: 5000,
        transportTotal: 2400,
        currency: 'MAD',
        travelStyle: 'Road trips',
        summary:
            'A slower road trip through kasbah country with short drives, local guesthouses, and flexible afternoons.',
      ),
      Trip(
        id: 'northern-colors',
        hostId: 'host-salma',
        hostName: 'Salma R.',
        hostHomeCity: 'Tangier',
        hostVerified: false,
        title: 'Northern colors',
        originCity: 'Tangier',
        startDate: northStart,
        endDate: northStart.add(const Duration(days: 3)),
        stops: [
          TripStop(
            city: 'Tetouan',
            arrivalDate: northStart,
            type: TripStopType.activity,
            travelMode: TripTravelMode.bus,
            travelDurationMinutes: 75,
          ),
          TripStop(
            city: 'Chefchaouen',
            arrivalDate: northStart.add(const Duration(days: 1)),
            type: TripStopType.overnight,
            travelMode: TripTravelMode.bus,
            travelDurationMinutes: 90,
          ),
        ],
        capacity: 4,
        confirmedTravelerCount: 1,
        lodgingTotal: 2800,
        transportTotal: 900,
        currency: 'MAD',
        travelStyle: 'Culture',
        summary:
            'Architecture, small museums, and slow café stops across two northern cities.',
      ),
    ];
  }
}
