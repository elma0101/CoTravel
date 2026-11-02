import '../../../core/l10n/app_strings.dart';
import 'trip.dart';

class TripRoutePoint {
  const TripRoutePoint({
    required this.index,
    required this.name,
    required this.date,
    required this.type,
    required this.coordinate,
    this.note,
    this.travelMode,
    this.travelDurationMinutes,
    this.isOptional = false,
    this.isOrigin = false,
  });

  final int index;
  final String name;
  final DateTime date;
  final TripStopType type;
  final GeoPoint? coordinate;
  final String? note;
  final TripTravelMode? travelMode;
  final int? travelDurationMinutes;
  final bool isOptional;
  final bool isOrigin;
}

class TripRoute {
  const TripRoute({required this.points});

  factory TripRoute.fromTrip(Trip trip) {
    return TripRoute(
      points: [
        TripRoutePoint(
          index: 0,
          name: trip.originCity,
          date: trip.startDate,
          type: TripStopType.waypoint,
          coordinate: MoroccoRouteCoordinates.lookup(trip.originCity),
          note: tr('Departure'),
          isOrigin: true,
        ),
        for (var index = 0; index < trip.stops.length; index++)
          TripRoutePoint(
            index: index + 1,
            name: trip.stops[index].city,
            date: trip.stops[index].arrivalDate,
            type: trip.stops[index].type,
            coordinate:
                trip.stops[index].coordinate ??
                MoroccoRouteCoordinates.lookup(trip.stops[index].city),
            note: trip.stops[index].notes,
            travelMode: trip.stops[index].travelMode,
            travelDurationMinutes: trip.stops[index].travelDurationMinutes,
            isOptional: trip.stops[index].isOptional,
          ),
      ],
    );
  }

  final List<TripRoutePoint> points;

  List<TripRoutePoint> get mappedPoints =>
      points.where((point) => point.coordinate != null).toList();

  bool get canExplore => mappedPoints.length >= 2;
}

abstract final class MoroccoRouteCoordinates {
  static const _places = <String, GeoPoint>{
    'agadir': GeoPoint(30.4278, -9.5981),
    'al hoceima': GeoPoint(35.2517, -3.9372),
    'asilah': GeoPoint(35.4656, -6.0340),
    'azrou': GeoPoint(33.4342, -5.2214),
    'beni mellal': GeoPoint(32.3373, -6.3498),
    'dakhla': GeoPoint(23.6848, -15.9580),
    'kenitra': GeoPoint(34.2610, -6.5802),
    'laayoune': GeoPoint(27.1253, -13.1625),
    'larache': GeoPoint(35.1932, -6.1557),
    'meknes': GeoPoint(33.8935, -5.5473),
    'midelt': GeoPoint(32.6852, -4.7451),
    'mohammedia': GeoPoint(33.6866, -7.3830),
    'nador': GeoPoint(35.1681, -2.9335),
    'oualidia': GeoPoint(32.7333, -9.0333),
    'oujda': GeoPoint(34.6814, -1.9086),
    'ouzoud': GeoPoint(32.0151, -6.7194),
    'safi': GeoPoint(32.2994, -9.2372),
    'sidi ifni': GeoPoint(29.3797, -10.1731),
    'tafraoute': GeoPoint(29.7167, -8.9667),
    'taroudant': GeoPoint(30.4703, -8.8770),
    'tinghir': GeoPoint(31.5147, -5.5328),
    'tiznit': GeoPoint(29.6974, -9.7316),
    'zagora': GeoPoint(30.3324, -5.8384),
    'agafay': GeoPoint(31.4481, -8.1814),
    'ait ben haddou': GeoPoint(31.0472, -7.1299),
    'akchour': GeoPoint(35.2444, -5.1740),
    'boumalne dades': GeoPoint(31.3734, -5.9957),
    'casablanca': GeoPoint(33.5731, -7.5898),
    'chefchaouen': GeoPoint(35.1688, -5.2636),
    'chigaga': GeoPoint(29.8270, -6.1710),
    'el jadida': GeoPoint(33.2316, -8.5007),
    'errachidia': GeoPoint(31.9314, -4.4240),
    'essaouira': GeoPoint(31.5085, -9.7595),
    'fes': GeoPoint(34.0181, -5.0078),
    'ifrane': GeoPoint(33.5228, -5.1106),
    'imlil': GeoPoint(31.1370, -7.9180),
    'marrakech': GeoPoint(31.6295, -7.9811),
    'marrakesh': GeoPoint(31.6295, -7.9811),
    'merzouga': GeoPoint(31.0802, -4.0133),
    'mhamid': GeoPoint(29.8267, -5.7230),
    'ouarzazate': GeoPoint(30.9335, -6.9370),
    'rabat': GeoPoint(34.0209, -6.8416),
    'skoura': GeoPoint(31.0606, -6.5566),
    'taghazout': GeoPoint(30.5457, -9.7080),
    'tangier': GeoPoint(35.7595, -5.8340),
    'tetouan': GeoPoint(35.5889, -5.3626),
  };

  static const _accents = {
    'à': 'a',
    'â': 'a',
    'ç': 'c',
    'è': 'e',
    'é': 'e',
    'ê': 'e',
    'î': 'i',
    'ï': 'i',
    'ô': 'o',
    'û': 'u',
  };

  static String _normalize(String value) {
    var text = value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
    _accents.forEach((accented, plain) {
      text = text.replaceAll(accented, plain);
    });
    return text;
  }

  /// The place itself, or else the town a label such as
  /// "Casa Voyageurs, Casablanca" names after its comma.
  static GeoPoint? lookup(String placeName) {
    final exact = _places[_normalize(placeName)];
    if (exact != null || !placeName.contains(',')) {
      return exact;
    }
    return _places[_normalize(placeName.split(',').last)];
  }

  /// Known place names matching [query], starting matches first.
  static List<String> search(String query, {int limit = 6}) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) {
      return const [];
    }
    final matches = _places.keys.where((name) => name.contains(normalized));
    final ordered = matches.toList()
      ..sort((left, right) {
        final leftStarts = left.startsWith(normalized);
        final rightStarts = right.startsWith(normalized);
        if (leftStarts != rightStarts) {
          return leftStarts ? -1 : 1;
        }
        return left.compareTo(right);
      });
    return ordered.take(limit).map(_displayName).toList(growable: false);
  }

  static String _displayName(String name) {
    return name
        .split(' ')
        .map((word) => '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  static TripStop resolve(TripStop stop) {
    if (stop.coordinate != null) {
      return stop;
    }
    final coordinate = lookup(stop.city);
    return coordinate == null
        ? stop
        : stop.copyWith(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
          );
  }
}
