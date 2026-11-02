import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/trip.dart';
import '../domain/trip_route.dart';

/// A place someone can pick for a departure or a stop.
class PlaceSuggestion {
  const PlaceSuggestion({
    required this.label,
    required this.coordinate,
    this.detail,
  });

  /// What is saved with the trip, such as "Casa Voyageurs, Casablanca".
  final String label;

  /// Where the place is, shown under the label.
  final String? detail;
  final GeoPoint coordinate;
}

abstract interface class PlaceSearch {
  Future<List<PlaceSuggestion>> search(
    String query, {
    required String language,
  });
}

/// The places built into the app. Works offline and in previews.
class BuiltInPlaceSearch implements PlaceSearch {
  const BuiltInPlaceSearch();

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    required String language,
  }) async {
    return [
      for (final name in MoroccoRouteCoordinates.search(query))
        PlaceSuggestion(
          label: name,
          coordinate: MoroccoRouteCoordinates.lookup(name)!,
        ),
    ];
  }
}

/// Searches OpenStreetMap through komoot's public Photon service, limited to
/// Morocco. Falls back to the built-in places when it cannot be reached.
class PhotonPlaceSearch implements PlaceSearch {
  PhotonPlaceSearch({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _fallback = BuiltInPlaceSearch();

  // Morocco, including the southern provinces.
  static const _boundingBox = '-17.2,20.7,-0.9,36.0';

  // The database accepts place names up to this length.
  static const _maxLabelLength = 80;

  @override
  Future<List<PlaceSuggestion>> search(
    String query, {
    required String language,
  }) async {
    final text = query.trim();
    if (text.length < 2) {
      return const [];
    }
    try {
      final response = await _client
          .get(
            Uri.https('photon.komoot.io', '/api/', {
              'q': text,
              'limit': '8',
              // Photon has no Arabic labels; French and English are supported.
              'lang': language == 'fr' ? 'fr' : 'en',
              'bbox': _boundingBox,
            }),
            headers: const {'User-Agent': 'CoTravel (com.cotravel.app)'},
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        return _fallback.search(text, language: language);
      }
      final suggestions = parsePhotonResponse(response.body);
      return suggestions.isEmpty
          ? _fallback.search(text, language: language)
          : suggestions;
    } on Object {
      return _fallback.search(text, language: language);
    }
  }

  /// Turns Photon's GeoJSON into suggestions, dropping repeats.
  static List<PlaceSuggestion> parsePhotonResponse(String body) {
    final features =
        (jsonDecode(body) as Map<String, dynamic>)['features'] as List? ??
        const [];
    final seen = <String>{};
    final suggestions = <PlaceSuggestion>[];
    for (final feature in features.cast<Map<String, dynamic>>()) {
      final properties =
          feature['properties'] as Map<String, dynamic>? ?? const {};
      final coordinates =
          (feature['geometry'] as Map<String, dynamic>?)?['coordinates']
              as List?;
      final name = _latinOnly(properties['name'] as String?);
      if (name == null || coordinates == null || coordinates.length < 2) {
        continue;
      }

      // A town is its own label; a station or landmark also names its town.
      final isSettlement = properties['osm_key'] == 'place';
      final town = _latinOnly(
        (properties['city'] ?? properties['town'] ?? properties['village'])
            as String?,
      );
      final region = _latinOnly(properties['state'] as String?);
      final label = isSettlement || town == null || town == name
          ? name
          : '$name, $town';
      if (label.length > _maxLabelLength || !seen.add(label.toLowerCase())) {
        continue;
      }

      // The label already names the town, so the detail narrows it down.
      final detail = isSettlement || town == null
          ? region
          : _latinOnly(properties['district'] as String?);

      suggestions.add(
        PlaceSuggestion(
          label: label,
          detail: detail,
          coordinate: GeoPoint(
            (coordinates[1] as num).toDouble(),
            (coordinates[0] as num).toDouble(),
          ),
        ),
      );
    }
    return suggestions;
  }

  // OpenStreetMap often adds Arabic and Tifinagh to Latin names, as in
  // "Et-taous ⵟⴰⵡⵙ الطاوس". The app's languages read the Latin part.
  static final _nonLatinScripts = RegExp('[؀-ۿݐ-ݿࢠ-ࣿⴰ-⵿]+');

  static String? _latinOnly(String? value) {
    if (value == null) {
      return null;
    }
    final cleaned = value
        .replaceAll(_nonLatinScripts, ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.length < 2 ? null : cleaned;
  }
}
