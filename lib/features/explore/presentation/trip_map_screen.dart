import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../trips/presentation/widgets/trip_card.dart';
import '../domain/trip_map_pins.dart';

class TripMapScreen extends ConsumerStatefulWidget {
  const TripMapScreen({super.key});

  @override
  ConsumerState<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends ConsumerState<TripMapScreen> {
  static const _pinColor = '#28584A';
  static const _pinTextColor = '#FFFFFA';

  MapLibreMapController? _controller;
  final _pinsByCircle = <String, TripMapPin>{};

  @override
  void dispose() {
    _controller?.onCircleTapped.remove(_onCircleTapped);
    super.dispose();
  }

  void _onCircleTapped(Circle circle) {
    final pin = _pinsByCircle[circle.id];
    if (pin != null) {
      _openPin(pin);
    }
  }

  Future<void> _drawPins(List<TripMapPin> pins) async {
    final controller = _controller;
    if (controller == null || pins.isEmpty) {
      return;
    }
    final geometry = [
      for (final pin in pins)
        LatLng(pin.coordinate.latitude, pin.coordinate.longitude),
    ];
    final circles = await controller.addCircles([
      for (final point in geometry)
        CircleOptions(
          geometry: point,
          circleRadius: 15,
          circleColor: _pinColor,
          circleStrokeColor: _pinTextColor,
          circleStrokeWidth: 3,
        ),
    ]);
    _pinsByCircle
      ..clear()
      ..addEntries([
        for (var index = 0; index < circles.length; index++)
          MapEntry(circles[index].id, pins[index]),
      ]);
    await controller.addSymbols([
      for (var index = 0; index < pins.length; index++)
        SymbolOptions(
          geometry: geometry[index],
          textField: '${pins[index].trips.length}',
          textSize: 12,
          textColor: _pinTextColor,
          textAnchor: 'center',
        ),
    ]);
  }

  void _openPin(TripMapPin pin) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => TripPinSheet(
        pin: pin,
        onOpenTrip: (tripId) {
          Navigator.pop(sheetContext);
          context.push(AppRoutes.tripDetails(tripId));
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);
    final mapStyleUrl = ref.watch(appConfigProvider).mapStyleUrl;
    final result = TripMapPins.fromTrips(catalog.discoverableTrips);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Trips on the map'))),
      body: Column(
        children: [
          Expanded(
            child: ColoredBox(
              color: AppColors.canvas,
              child: MapLibreMap(
                key: const ValueKey('trip-map'),
                styleString: mapStyleUrl,
                // Centered on Morocco, where the PoC runs.
                initialCameraPosition: const CameraPosition(
                  target: LatLng(31.7917, -7.0926),
                  zoom: 4.6,
                ),
                onMapCreated: (controller) {
                  _controller = controller;
                  controller.onCircleTapped.add(_onCircleTapped);
                },
                onStyleLoadedCallback: () => unawaited(_drawPins(result.pins)),
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                annotationOrder: const [
                  AnnotationType.circle,
                  AnnotationType.symbol,
                ],
              ),
            ),
          ),
          TripPinsBar(result: result, onSelected: _openPin),
        ],
      ),
    );
  }
}

/// Map markers are not reachable by screen readers, so every pin is also here.
class TripPinsBar extends StatelessWidget {
  const TripPinsBar({
    required this.result,
    required this.onSelected,
    super.key,
  });

  final TripMapPins result;
  final ValueChanged<TripMapPin> onSelected;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (result.pins.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Text(tr('No trips to show on the map.')),
                )
              else
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: Row(
                    children: [
                      for (final pin in result.pins)
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.xs),
                          child: ActionChip(
                            key: ValueKey('trip-pin-${pin.place}'),
                            label: Text('${pin.place} (${pin.trips.length})'),
                            onPressed: () => onSelected(pin),
                          ),
                        ),
                    ],
                  ),
                ),
              if (result.unmappedCount > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.xs,
                    AppSpacing.lg,
                    0,
                  ),
                  child: Text(
                    trPlural(
                      result.unmappedCount,
                      '{n} trip has no map location and is only in the list.',
                      '{n} trips have no map location and are only in the list.',
                    ),
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TripPinSheet extends StatelessWidget {
  const TripPinSheet({required this.pin, required this.onOpenTrip, super.key});

  final TripMapPin pin;
  final ValueChanged<String> onOpenTrip;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.75,
        ),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          children: [
            Text(pin.place, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            for (final trip in pin.trips) ...[
              TripCard(trip: trip, onTap: () => onOpenTrip(trip.id)),
              const SizedBox(height: AppSpacing.md),
            ],
          ],
        ),
      ),
    );
  }
}
