import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/user_profile.dart';
import '../../trips/data/trip_repository.dart';
import '../../trips/domain/trip.dart';
import '../domain/trip_join_request.dart';

abstract interface class JoinRequestRepository {
  Future<List<TripJoinRequest>> fetchTravelerRequests(String userId);

  Future<List<TripJoinRequest>> fetchHostRequests(String userId);

  Future<TripJoinRequest> createRequest({
    required Trip trip,
    required UserProfile traveler,
    required String message,
  });

  Future<TripJoinRequest> reviewAsHost({
    required String requestId,
    required bool accept,
  });

  Future<TripJoinRequest> confirmAsTraveler({
    required String requestId,
    required bool confirm,
  });

  Future<TripJoinRequest> withdrawRequest(String requestId);
}

class SupabaseJoinRequestRepository implements JoinRequestRepository {
  SupabaseJoinRequestRepository(this._client);

  static const _selection = '''
    *,
    trip:trips!inner(
      host_id,
      title,
      origin_city,
      destination_city,
      start_date
    ),
    traveler:profiles!trip_join_requests_traveler_id_fkey(
      display_name,
      bio,
      home_city,
      linkedin_verified_at
    )
  ''';

  final SupabaseClient _client;

  @override
  Future<List<TripJoinRequest>> fetchTravelerRequests(String userId) async {
    final rows = await _client
        .from('trip_join_requests')
        .select(_selection)
        .eq('traveler_id', userId)
        .order('created_at', ascending: false);
    return rows.map(_fromMap).toList();
  }

  @override
  Future<List<TripJoinRequest>> fetchHostRequests(String userId) async {
    final rows = await _client
        .from('trip_join_requests')
        .select(_selection)
        .eq('trip.host_id', userId)
        .order('created_at', ascending: false);
    return rows.map(_fromMap).toList();
  }

  @override
  Future<TripJoinRequest> createRequest({
    required Trip trip,
    required UserProfile traveler,
    required String message,
  }) async {
    final requestId = await _client.rpc(
      'create_join_request',
      params: {'p_trip_id': trip.id, 'p_message': message},
    );
    return _fetchRequest(requestId as String);
  }

  @override
  Future<TripJoinRequest> reviewAsHost({
    required String requestId,
    required bool accept,
  }) async {
    await _client.rpc(
      'review_join_request',
      params: {'p_request_id': requestId, 'p_accept': accept},
    );
    return _fetchRequest(requestId);
  }

  @override
  Future<TripJoinRequest> confirmAsTraveler({
    required String requestId,
    required bool confirm,
  }) async {
    await _client.rpc(
      'confirm_join_request',
      params: {'p_request_id': requestId, 'p_confirm': confirm},
    );
    return _fetchRequest(requestId);
  }

  @override
  Future<TripJoinRequest> withdrawRequest(String requestId) async {
    await _client.rpc(
      'withdraw_join_request',
      params: {'p_request_id': requestId},
    );
    return _fetchRequest(requestId);
  }

  Future<TripJoinRequest> _fetchRequest(String requestId) async {
    final row = await _client
        .from('trip_join_requests')
        .select(_selection)
        .eq('id', requestId)
        .single();
    return _fromMap(row);
  }

  TripJoinRequest _fromMap(Map<String, dynamic> row) {
    final trip = row['trip'] as Map<String, dynamic>;
    final traveler = row['traveler'] as Map<String, dynamic>;
    return TripJoinRequest(
      id: row['id'] as String,
      tripId: row['trip_id'] as String,
      hostId: trip['host_id'] as String,
      tripTitle: trip['title'] as String,
      originCity: trip['origin_city'] as String,
      destinationCity: trip['destination_city'] as String,
      startDate: DateTime.parse(trip['start_date'] as String),
      travelerId: row['traveler_id'] as String,
      travelerName: traveler['display_name'] as String? ?? 'CoTravel traveler',
      travelerBio: traveler['bio'] as String?,
      travelerHomeCity: traveler['home_city'] as String?,
      travelerVerified: traveler['linkedin_verified_at'] != null,
      message: row['message'] as String,
      status: _statusFromDatabase(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
    );
  }

  JoinRequestStatus _statusFromDatabase(String value) {
    return switch (value) {
      'pending_host' => JoinRequestStatus.pendingHost,
      'pending_traveler' => JoinRequestStatus.pendingTraveler,
      'confirmed' => JoinRequestStatus.confirmed,
      'declined' => JoinRequestStatus.declined,
      'withdrawn' => JoinRequestStatus.withdrawn,
      _ => throw StateError('Unsupported join request status: $value'),
    };
  }
}

class PreviewJoinRequestRepository implements JoinRequestRepository {
  PreviewJoinRequestRepository({
    required PreviewTripRepository tripRepository,
    DateTime? now,
    Future<void> Function(TripJoinRequest request)? onConfirmed,
  }) : this._(tripRepository, now ?? DateTime.now(), onConfirmed);

  PreviewJoinRequestRepository._(
    this._tripRepository,
    DateTime now,
    this._onConfirmed,
  ) : _requests = _seedRequests(now);

  final PreviewTripRepository _tripRepository;
  final Future<void> Function(TripJoinRequest request)? _onConfirmed;
  final List<TripJoinRequest> _requests;
  int _nextId = 1;

  @override
  Future<List<TripJoinRequest>> fetchTravelerRequests(String userId) async {
    return _requests.where((request) => request.travelerId == userId).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  @override
  Future<List<TripJoinRequest>> fetchHostRequests(String userId) async {
    return _requests.where((request) => request.hostId == userId).toList()
      ..sort((left, right) => right.createdAt.compareTo(left.createdAt));
  }

  @override
  Future<TripJoinRequest> createRequest({
    required Trip trip,
    required UserProfile traveler,
    required String message,
  }) async {
    if (trip.hostId == traveler.id) {
      throw StateError('You cannot request to join your own trip.');
    }
    if (trip.openSeats <= 0) {
      throw StateError('This trip is full.');
    }
    if (_requests.any(
      (request) =>
          request.tripId == trip.id &&
          request.travelerId == traveler.id &&
          request.status.isActive,
    )) {
      throw StateError('You already have an active request for this trip.');
    }

    final request = TripJoinRequest(
      id: 'preview-request-${_nextId++}',
      tripId: trip.id,
      hostId: trip.hostId,
      tripTitle: trip.title,
      originCity: trip.originCity,
      destinationCity: trip.destinationCity,
      startDate: trip.startDate,
      travelerId: traveler.id,
      travelerName: traveler.displayName ?? 'Preview traveler',
      travelerBio: traveler.bio,
      travelerHomeCity: traveler.homeCity,
      travelerVerified: traveler.isLinkedInVerified,
      message: message,
      status: JoinRequestStatus.pendingHost,
      createdAt: DateTime.now(),
    );
    _requests.add(request);
    return request;
  }

  @override
  Future<TripJoinRequest> reviewAsHost({
    required String requestId,
    required bool accept,
  }) async {
    final request = _requireRequest(requestId);
    if (request.status != JoinRequestStatus.pendingHost) {
      throw StateError('This request has already been reviewed.');
    }
    return _replace(
      request,
      accept ? JoinRequestStatus.pendingTraveler : JoinRequestStatus.declined,
    );
  }

  @override
  Future<TripJoinRequest> confirmAsTraveler({
    required String requestId,
    required bool confirm,
  }) async {
    final request = _requireRequest(requestId);
    if (request.status != JoinRequestStatus.pendingTraveler) {
      throw StateError(
        'This request is not waiting for traveler confirmation.',
      );
    }
    if (confirm) {
      await _tripRepository.confirmTraveler(request.tripId);
      await _onConfirmed?.call(request);
    }
    return _replace(
      request,
      confirm ? JoinRequestStatus.confirmed : JoinRequestStatus.withdrawn,
    );
  }

  @override
  Future<TripJoinRequest> withdrawRequest(String requestId) async {
    final request = _requireRequest(requestId);
    if (request.status != JoinRequestStatus.pendingHost) {
      throw StateError('Only a pending request can be withdrawn.');
    }
    return _replace(request, JoinRequestStatus.withdrawn);
  }

  TripJoinRequest _requireRequest(String requestId) {
    return _requests.firstWhere(
      (request) => request.id == requestId,
      orElse: () => throw StateError('Join request not found.'),
    );
  }

  TripJoinRequest _replace(TripJoinRequest request, JoinRequestStatus status) {
    final updated = request.copyWith(status: status);
    _requests[_requests.indexWhere((item) => item.id == request.id)] = updated;
    return updated;
  }

  static List<TripJoinRequest> _seedRequests(DateTime value) {
    final today = DateTime(value.year, value.month, value.day);
    return [
      TripJoinRequest(
        id: 'preview-atlas-approval',
        tripId: 'atlas-weekend',
        hostId: 'host-amina',
        tripTitle: 'Atlas villages weekend',
        originCity: 'Casablanca',
        destinationCity: 'Imlil',
        startDate: today.add(const Duration(days: 17)),
        travelerId: 'preview-user',
        travelerName: 'Preview traveler',
        travelerBio: 'Curious about new places and thoughtful group travel.',
        travelerHomeCity: 'Casablanca',
        travelerVerified: true,
        message:
            'The pace sounds ideal. I enjoy small groups and have done several easy mountain walks.',
        status: JoinRequestStatus.pendingTraveler,
        createdAt: today.subtract(const Duration(hours: 8)),
      ),
      TripJoinRequest(
        id: 'preview-coast-request',
        tripId: 'essaouira-coast',
        hostId: 'host-youssef',
        tripTitle: 'Coast, food, and surf',
        originCity: 'Rabat',
        destinationCity: 'Essaouira',
        startDate: today.add(const Duration(days: 31)),
        travelerId: 'preview-user',
        travelerName: 'Preview traveler',
        travelerBio: 'Curious about new places and thoughtful group travel.',
        travelerHomeCity: 'Casablanca',
        travelerVerified: true,
        message:
            'I would love the market visits and I am comfortable sharing the driving.',
        status: JoinRequestStatus.pendingHost,
        createdAt: today.subtract(const Duration(days: 1)),
      ),
      TripJoinRequest(
        id: 'preview-dades-confirmed',
        tripId: 'dades-slow-road',
        hostId: 'host-leila',
        tripTitle: 'Dades slow road',
        originCity: 'Marrakech',
        destinationCity: 'Boumalne Dades',
        startDate: today.add(const Duration(days: 38)),
        travelerId: 'preview-user',
        travelerName: 'Preview traveler',
        travelerBio: 'Curious about new places and thoughtful group travel.',
        travelerHomeCity: 'Casablanca',
        travelerVerified: true,
        message:
            'The slower pace is exactly what I look for, and I am happy to help compare guesthouses.',
        status: JoinRequestStatus.confirmed,
        createdAt: today.subtract(const Duration(days: 3)),
      ),
      TripJoinRequest(
        id: 'preview-nadia-request',
        tripId: 'preview-rif-loop',
        hostId: 'preview-user',
        tripTitle: 'Rif towns and trails',
        originCity: 'Casablanca',
        destinationCity: 'Chefchaouen',
        startDate: today.add(const Duration(days: 24)),
        travelerId: 'traveler-nadia',
        travelerName: 'Nadia K.',
        travelerBio:
            'Museum lover, weekend hiker, and reliably early for every train.',
        travelerHomeCity: 'Rabat',
        travelerVerified: true,
        message:
            'I like the mix of towns and trails. I hike regularly and prefer the same calm pace you described.',
        status: JoinRequestStatus.pendingHost,
        createdAt: today.subtract(const Duration(hours: 3)),
      ),
    ];
  }
}
