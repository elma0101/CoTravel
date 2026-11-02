import 'dart:convert';

import 'package:cotravel_app/app/providers/app_providers.dart';
import 'package:cotravel_app/features/trips/data/place_search.dart';
import 'package:cotravel_app/features/trips/domain/trip.dart';
import 'package:cotravel_app/features/trips/domain/trip_route.dart';
import 'package:cotravel_app/features/trips/presentation/widgets/place_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, Object?> _feature({
  required String name,
  required String osmKey,
  required double longitude,
  required double latitude,
  String? city,
  String? district,
  String? state,
}) {
  return {
    'type': 'Feature',
    'geometry': {
      'type': 'Point',
      'coordinates': [longitude, latitude],
    },
    'properties': {
      'name': name,
      'osm_key': osmKey,
      'city': ?city,
      'district': ?district,
      'state': ?state,
    },
  };
}

String _response(List<Map<String, Object?>> features) {
  return jsonEncode({'type': 'FeatureCollection', 'features': features});
}

class _FixedPlaceSearch implements PlaceSearch {
  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    required String language,
  }) async {
    return const [
      PlaceSuggestion(
        label: 'Casa Voyageurs, Casablanca',
        detail: 'Roches Noires',
        coordinate: GeoPoint(33.5902, -7.5900),
      ),
    ];
  }
}

void main() {
  test('a station names its town and keeps its own coordinates', () {
    final suggestions = PhotonPlaceSearch.parsePhotonResponse(
      _response([
        _feature(
          name: 'Casa Voyageurs',
          osmKey: 'railway',
          longitude: -7.5900,
          latitude: 33.5902,
          city: 'Casablanca',
          district: 'Arrondissement des Roches noires',
        ),
      ]),
    );

    final station = suggestions.single;
    expect(station.label, 'Casa Voyageurs, Casablanca');
    expect(station.detail, 'Arrondissement des Roches noires');
    expect(station.coordinate.latitude, 33.5902);
    expect(station.coordinate.longitude, -7.5900);
  });

  test('a town is its own label and shows its region', () {
    final suggestions = PhotonPlaceSearch.parsePhotonResponse(
      _response([
        _feature(
          name: 'Merzouga',
          osmKey: 'place',
          longitude: -4.0133,
          latitude: 31.0802,
          city: 'Et-taous ⵟⴰⵡⵙ الطاوس',
          state: 'Drâa-Tafilalet',
        ),
      ]),
    );

    expect(suggestions.single.label, 'Merzouga');
    expect(suggestions.single.detail, 'Drâa-Tafilalet');
  });

  test('Arabic and Tifinagh are dropped and repeats are merged', () {
    final camp = _feature(
      name: 'Merzouga Desert Camp',
      osmKey: 'tourism',
      longitude: -4.01,
      latitude: 31.08,
      city: 'Et-taous ⵟⴰⵡⵙ الطاوس',
    );
    final suggestions = PhotonPlaceSearch.parsePhotonResponse(
      _response([camp, camp]),
    );

    expect(suggestions.single.label, 'Merzouga Desert Camp, Et-taous');
  });

  test('a failed search falls back to the built-in places', () async {
    final search = PhotonPlaceSearch(
      client: MockClient((request) async => http.Response('down', 503)),
    );

    final suggestions = await search.search('marrak', language: 'fr');

    expect(suggestions.map((place) => place.label), contains('Marrakech'));
  });

  test('the search asks for Morocco in the app language', () async {
    late Uri asked;
    final search = PhotonPlaceSearch(
      client: MockClient((request) async {
        asked = request.url;
        return http.Response(_response(const []), 200);
      }),
    );

    await search.search('Casa', language: 'fr');

    expect(asked.host, 'photon.komoot.io');
    expect(asked.queryParameters['lang'], 'fr');
    expect(asked.queryParameters['bbox'], isNotEmpty);
  });

  test('a station label finds its town on the map', () {
    expect(
      MoroccoRouteCoordinates.lookup('Casa Voyageurs, Casablanca'),
      MoroccoRouteCoordinates.lookup('Casablanca'),
    );
    expect(MoroccoRouteCoordinates.lookup('Somewhere, Nowhere'), isNull);
  });

  testWidgets('picking a suggestion hands over its coordinates', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    PlaceSuggestion? picked;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [placeSearchProvider.overrideWithValue(_FixedPlaceSearch())],
        child: MaterialApp(
          home: Scaffold(
            body: PlaceField(
              fieldKey: const ValueKey('place'),
              controller: controller,
              label: 'Leaving from',
              icon: Icons.trip_origin_rounded,
              validator: (_) => null,
              onPicked: (place) => picked = place,
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const ValueKey('place')), 'Casa voy');
    // Suggestions wait for typing to pause.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('This place will not appear on the map.'), findsOneWidget);

    await tester.tap(find.text('Casa Voyageurs, Casablanca'));
    await tester.pumpAndSettle();

    expect(controller.text, 'Casa Voyageurs, Casablanca');
    expect(picked?.coordinate.latitude, 33.5902);
    expect(find.text('This place will not appear on the map.'), findsNothing);
  });
}
