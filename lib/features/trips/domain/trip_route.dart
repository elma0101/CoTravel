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
          note: 'Departure',
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

  static GeoPoint? lookup(String placeName) {
    final normalized = placeName.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return _places[normalized];
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
