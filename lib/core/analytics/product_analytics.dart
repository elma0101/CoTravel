import 'package:supabase_flutter/supabase_flutter.dart';

enum ProductEvent {
  previewSignedIn('preview_signed_in'),
  profileCompleted('profile_completed'),
  profileVerified('profile_verified'),
  tripBuilderOpened('trip_builder_opened'),
  tripPublished('trip_published'),
  joinRequestSubmitted('join_request_submitted'),
  tripPlaceConfirmed('trip_place_confirmed'),
  groupCreated('group_created'),
  conversationOpened('conversation_opened'),
  safetyReportSubmitted('safety_report_submitted'),
  userBlocked('user_blocked');

  const ProductEvent(this.databaseValue);

  final String databaseValue;
}

class AnalyticsEvent {
  const AnalyticsEvent({
    required this.event,
    required this.occurredAt,
    this.tripId,
    this.properties = const {},
  });

  final ProductEvent event;
  final String? tripId;
  final Map<String, Object?> properties;
  final DateTime occurredAt;
}

abstract interface class ProductAnalytics {
  Future<void> track(
    ProductEvent event, {
    String? tripId,
    Map<String, Object?> properties = const {},
  });
}

class SupabaseProductAnalytics implements ProductAnalytics {
  SupabaseProductAnalytics(this._client);

  final SupabaseClient _client;

  @override
  Future<void> track(
    ProductEvent event, {
    String? tripId,
    Map<String, Object?> properties = const {},
  }) async {
    try {
      await _client.rpc(
        'track_product_event',
        params: {
          'p_event_name': event.databaseValue,
          'p_trip_id': tripId,
          'p_properties': properties,
        },
      );
    } on Object {
      // Product analytics must never break a user workflow.
    }
  }
}

class PreviewProductAnalytics implements ProductAnalytics {
  final List<AnalyticsEvent> _events = [];

  List<AnalyticsEvent> get events => List.unmodifiable(_events);

  @override
  Future<void> track(
    ProductEvent event, {
    String? tripId,
    Map<String, Object?> properties = const {},
  }) async {
    _events.add(
      AnalyticsEvent(
        event: event,
        tripId: tripId,
        properties: properties,
        occurredAt: DateTime.now(),
      ),
    );
  }
}

class NoopProductAnalytics implements ProductAnalytics {
  const NoopProductAnalytics();

  @override
  Future<void> track(
    ProductEvent event, {
    String? tripId,
    Map<String, Object?> properties = const {},
  }) async {}
}
