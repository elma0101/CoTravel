import 'package:flutter/material.dart';

import '../../domain/trip.dart';

class TripCoverPhoto {
  const TripCoverPhoto({
    required this.assetPath,
    required this.placeLabel,
    required this.semanticLabel,
    required this.photographer,
    required this.sourceUrl,
    required this.licenseName,
    required this.licenseUrl,
    this.alignment = Alignment.center,
  });

  final String assetPath;
  final String placeLabel;
  final String semanticLabel;
  final String photographer;
  final String sourceUrl;
  final String licenseName;
  final String licenseUrl;
  final Alignment alignment;
}

abstract final class TripCoverImages {
  static const _imlil = TripCoverPhoto(
    assetPath: 'assets/images/trips/atlas_imlil.jpg',
    placeLabel: 'Imlil · High Atlas',
    semanticLabel: 'Mountain villages and green valley around Imlil',
    photographer: 'DimiTalen',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Overview_of_Imlil_from_Aroumd,_Morocco,_2008.jpg',
    licenseName: 'CC0 1.0',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    alignment: Alignment(0, 0.2),
  );

  static const _akchour = TripCoverPhoto(
    assetPath: 'assets/images/trips/rif_akchour.jpg',
    placeLabel: 'Akchour · Rif Mountains',
    semanticLabel: 'Rocky river trail through the Akchour mountains',
    photographer: 'Sgroey',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Akchour_waterfall_trail.jpg',
    licenseName: 'CC BY 4.0',
    licenseUrl: 'https://creativecommons.org/licenses/by/4.0/',
    alignment: Alignment(0, 0.45),
  );

  static const _essaouira = TripCoverPhoto(
    assetPath: 'assets/images/trips/coast_essaouira.jpg',
    placeLabel: 'Essaouira · Atlantic coast',
    semanticLabel: 'Rocky Atlantic coastline at Essaouira',
    photographer: 'Mustang Joe',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Essaouira_Coastline,_Morocco.jpg',
    licenseName: 'CC0 1.0',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    alignment: Alignment(0, 0.25),
  );

  static const _dades = TripCoverPhoto(
    assetPath: 'assets/images/trips/dades_road.jpg',
    placeLabel: 'Dadès Gorge',
    semanticLabel: 'Winding mountain road through the Dadès Gorge',
    photographer: 'Anderson sady',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Winding_road_leading_into_the_Dades_gorges_in_the_Anti-Atlas_mountain_range,_Morocco.jpg',
    licenseName: 'CC BY-SA 3.0',
    licenseUrl: 'https://creativecommons.org/licenses/by-sa/3.0/',
  );

  static const _chefchaouen = TripCoverPhoto(
    assetPath: 'assets/images/trips/north_chefchaouen.jpg',
    placeLabel: 'Chefchaouen · Medina',
    semanticLabel: 'Blue-painted medina street in Chefchaouen',
    photographer: 'Doalex',
    sourceUrl:
        'https://commons.wikimedia.org/wiki/File:Medina_of_Chefchaouen.jpg',
    licenseName: 'CC0 1.0',
    licenseUrl: 'https://creativecommons.org/publicdomain/zero/1.0/',
    alignment: Alignment(0, 0.35),
  );

  static const _previewTrips = <String, TripCoverPhoto>{
    'atlas-weekend': _imlil,
    'preview-rif-loop': _akchour,
    'essaouira-coast': _essaouira,
    'dades-slow-road': _dades,
    'northern-colors': _chefchaouen,
  };

  static const _places = <String, TripCoverPhoto>{
    'imlil': _imlil,
    'akchour': _akchour,
    'essaouira': _essaouira,
    'boumalne dades': _dades,
    'chefchaouen': _chefchaouen,
  };

  static TripCoverPhoto? forTrip(Trip trip) {
    final previewCover = _previewTrips[trip.id];
    if (previewCover != null) {
      return previewCover;
    }

    for (final stop in trip.stops.reversed) {
      final cover = _places[_normalize(stop.city)];
      if (cover != null) {
        return cover;
      }
    }
    return _places[_normalize(trip.originCity)];
  }

  static String _normalize(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }
}
