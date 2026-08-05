import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/trip.dart';
import '../domain/trip_route.dart';
import 'trip_formatters.dart';

class RouteExplorerScreen extends ConsumerStatefulWidget {
  const RouteExplorerScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<RouteExplorerScreen> createState() =>
      _RouteExplorerScreenState();
}

class _RouteExplorerScreenState extends ConsumerState<RouteExplorerScreen> {
  late Future<Trip?> _trip;

  @override
  void initState() {
    super.initState();
    _trip = ref.read(tripCatalogProvider).findTrip(widget.tripId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Trip?>(
      future: _trip,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final trip = snapshot.data;
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Explore route')),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.map_outlined, size: 42),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'This route is no longer available.',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => context.pop(),
                      child: const Text('Go back'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return _InteractiveRouteExplorer(
          trip: trip,
          mapStyleUrl: ref.watch(appConfigProvider).mapStyleUrl,
        );
      },
    );
  }
}

class _InteractiveRouteExplorer extends StatefulWidget {
  const _InteractiveRouteExplorer({
    required this.trip,
    required this.mapStyleUrl,
  });

  final Trip trip;
  final String mapStyleUrl;

  @override
  State<_InteractiveRouteExplorer> createState() =>
      _InteractiveRouteExplorerState();
}

class _InteractiveRouteExplorerState extends State<_InteractiveRouteExplorer> {
  static const _routeColor = '#C97858';
  static const _routeUnderlayColor = '#F2DED5';
  static const _inactiveMarkerColor = '#28584A';
  static const _markerTextColor = '#FFFFFA';

  late final TripRoute _route;
  late final List<GlobalKey> _pointKeys;
  final _sheetController = DraggableScrollableController();

  MapLibreMapController? _mapController;
  List<Circle> _markers = const [];
  final Map<String, int> _markerPointIndexes = {};
  final Map<String, int> _labelPointIndexes = {};
  int _selectedIndex = 0;
  bool _guidedMode = false;
  bool _mapReady = false;
  bool _drawingRoute = false;
  String? _mapError;

  @override
  void initState() {
    super.initState();
    _route = TripRoute.fromTrip(widget.trip);
    _pointKeys = List.generate(_route.points.length, (_) => GlobalKey());
  }

  @override
  void dispose() {
    final controller = _mapController;
    if (controller != null) {
      controller.onCircleTapped.remove(_onCircleTapped);
      controller.onSymbolTapped.remove(_onSymbolTapped);
    }
    _sheetController.dispose();
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _mapController = controller;
    controller.onCircleTapped.add(_onCircleTapped);
    controller.onSymbolTapped.add(_onSymbolTapped);
  }

  void _onCircleTapped(Circle circle) {
    final pointIndex = _markerPointIndexes[circle.id];
    if (pointIndex != null) {
      unawaited(_selectPoint(pointIndex, revealCard: true));
    }
  }

  void _onSymbolTapped(Symbol symbol) {
    final pointIndex = _labelPointIndexes[symbol.id];
    if (pointIndex != null) {
      unawaited(_selectPoint(pointIndex, revealCard: true));
    }
  }

  Future<void> _drawRoute() async {
    final controller = _mapController;
    if (controller == null || _drawingRoute) {
      return;
    }
    _drawingRoute = true;
    try {
      final mappedPoints = _route.mappedPoints;
      final geometry = mappedPoints
          .map(
            (point) =>
                LatLng(point.coordinate!.latitude, point.coordinate!.longitude),
          )
          .toList();

      if (geometry.length >= 2) {
        await controller.addLines([
          LineOptions(
            geometry: geometry,
            lineColor: _routeUnderlayColor,
            lineWidth: 9,
            lineOpacity: 0.95,
            lineJoin: 'round',
          ),
          LineOptions(
            geometry: geometry,
            lineColor: _routeColor,
            lineWidth: 4,
            lineOpacity: 0.95,
            lineJoin: 'round',
          ),
        ]);
      }

      _markers = await controller.addCircles(
        [
          for (final point in mappedPoints)
            CircleOptions(
              geometry: LatLng(
                point.coordinate!.latitude,
                point.coordinate!.longitude,
              ),
              circleRadius: point.index == _selectedIndex ? 18 : 14,
              circleColor: point.index == _selectedIndex
                  ? _routeColor
                  : _inactiveMarkerColor,
              circleStrokeColor: '#FFFFFA',
              circleStrokeWidth: 3,
              circleOpacity: 1,
            ),
        ],
        [
          for (final point in mappedPoints) {'pointIndex': point.index},
        ],
      );
      _markerPointIndexes
        ..clear()
        ..addEntries(
          _markers.map(
            (marker) => MapEntry(
              marker.id,
              (marker.data?['pointIndex'] as num).toInt(),
            ),
          ),
        );

      final labels = await controller.addSymbols(
        [
          for (final point in mappedPoints)
            SymbolOptions(
              geometry: LatLng(
                point.coordinate!.latitude,
                point.coordinate!.longitude,
              ),
              textField: '${point.index + 1}',
              textSize: 12,
              textColor: _markerTextColor,
              textHaloColor: _markerTextColor,
              textHaloWidth: 0.4,
              textAnchor: 'center',
            ),
        ],
        [
          for (final point in mappedPoints) {'pointIndex': point.index},
        ],
      );
      _labelPointIndexes
        ..clear()
        ..addEntries(
          labels.map(
            (label) =>
                MapEntry(label.id, (label.data?['pointIndex'] as num).toInt()),
          ),
        );

      await _fitRoute();
      if (mounted) {
        setState(() {
          _mapReady = true;
          _mapError = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _mapError = 'The route map could not be prepared.';
        });
      }
    } finally {
      _drawingRoute = false;
    }
  }

  Future<void> _fitRoute() async {
    final controller = _mapController;
    final points = _route.mappedPoints;
    if (controller == null || points.isEmpty) {
      return;
    }

    if (points.length == 1) {
      final coordinate = points.single.coordinate!;
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(coordinate.latitude, coordinate.longitude),
          10,
        ),
      );
      return;
    }

    var minLatitude = points.first.coordinate!.latitude;
    var maxLatitude = minLatitude;
    var minLongitude = points.first.coordinate!.longitude;
    var maxLongitude = minLongitude;
    for (final point in points.skip(1)) {
      final coordinate = point.coordinate!;
      minLatitude = coordinate.latitude < minLatitude
          ? coordinate.latitude
          : minLatitude;
      maxLatitude = coordinate.latitude > maxLatitude
          ? coordinate.latitude
          : maxLatitude;
      minLongitude = coordinate.longitude < minLongitude
          ? coordinate.longitude
          : minLongitude;
      maxLongitude = coordinate.longitude > maxLongitude
          ? coordinate.longitude
          : maxLongitude;
    }

    await controller.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLatitude, minLongitude),
          northeast: LatLng(maxLatitude, maxLongitude),
        ),
        left: 44,
        top: 110,
        right: 44,
        bottom: 280,
      ),
    );
  }

  Future<void> _selectPoint(int index, {bool revealCard = false}) async {
    if (index < 0 || index >= _route.points.length) {
      return;
    }
    if (mounted) {
      setState(() => _selectedIndex = index);
    }

    final controller = _mapController;
    final point = _route.points[index];
    final coordinate = point.coordinate;
    if (controller != null && coordinate != null) {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(
          LatLng(coordinate.latitude, coordinate.longitude),
          10.5,
        ),
      );
      await Future.wait([
        for (final marker in _markers)
          controller.updateCircle(
            marker,
            CircleOptions(
              circleRadius: _markerPointIndexes[marker.id] == index ? 18 : 14,
              circleColor: _markerPointIndexes[marker.id] == index
                  ? _routeColor
                  : _inactiveMarkerColor,
            ),
          ),
      ]);
    }

    if (revealCard && !_guidedMode) {
      if (_sheetController.isAttached) {
        await _sheetController.animateTo(
          0.58,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _pointKeys[index].currentContext;
        if (context != null) {
          unawaited(
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: 0.18,
            ),
          );
        }
      });
    }
  }

  Future<void> _startGuidedMode() async {
    setState(() {
      _guidedMode = true;
      _selectedIndex = 0;
    });
    if (_sheetController.isAttached) {
      await _sheetController.animateTo(
        0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
    await _selectPoint(0);
  }

  Future<void> _leaveGuidedMode() async {
    setState(() => _guidedMode = false);
    if (_sheetController.isAttached) {
      await _sheetController.animateTo(
        0.34,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mappedPoints = _route.mappedPoints;
    final initialCoordinate = mappedPoints.isEmpty
        ? const GeoPoint(31.7917, -7.0926)
        : mappedPoints.first.coordinate!;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.canvas,
              child: MapLibreMap(
                key: const ValueKey('route-explorer-map'),
                styleString: widget.mapStyleUrl,
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    initialCoordinate.latitude,
                    initialCoordinate.longitude,
                  ),
                  zoom: mappedPoints.length > 1 ? 5.5 : 10,
                ),
                onMapCreated: _onMapCreated,
                onStyleLoadedCallback: () => unawaited(_drawRoute()),
                compassEnabled: false,
                rotateGesturesEnabled: false,
                tiltGesturesEnabled: false,
                annotationOrder: const [
                  AnnotationType.line,
                  AnnotationType.circle,
                  AnnotationType.symbol,
                ],
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Row(
                  children: [
                    _MapActionButton(
                      tooltip: 'Back to trip',
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => context.pop(),
                    ),
                    const Spacer(),
                    _MapActionButton(
                      key: const ValueKey('show-entire-route'),
                      tooltip: 'Show entire route',
                      icon: Icons.route_rounded,
                      onPressed: mappedPoints.isEmpty
                          ? null
                          : () => unawaited(_fitRoute()),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!_mapReady && _mapError == null)
            const Positioned(
              top: 88,
              left: 0,
              right: 0,
              child: Center(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: AppSpacing.sm),
                        Text('Preparing route…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (_mapError != null)
            Positioned(
              top: 88,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: Material(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Row(
                    children: [
                      const Icon(Icons.map_outlined, color: AppColors.error),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(child: Text(_mapError!)),
                    ],
                  ),
                ),
              ),
            ),
          DraggableScrollableSheet(
            key: const ValueKey('route-itinerary-sheet'),
            controller: _sheetController,
            initialChildSize: 0.34,
            minChildSize: 0.18,
            maxChildSize: 0.82,
            snap: true,
            snapSizes: const [0.34, 0.58, 0.82],
            builder: (context, scrollController) {
              return Material(
                color: AppColors.surface,
                elevation: 12,
                shadowColor: Colors.black26,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                clipBehavior: Clip.antiAlias,
                child: _guidedMode
                    ? _GuidedRouteSheet(
                        trip: widget.trip,
                        point: _route.points[_selectedIndex],
                        pointCount: _route.points.length,
                        scrollController: scrollController,
                        onPrevious: _selectedIndex == 0
                            ? null
                            : () => unawaited(_selectPoint(_selectedIndex - 1)),
                        onNext: _selectedIndex == _route.points.length - 1
                            ? _leaveGuidedMode
                            : () => unawaited(_selectPoint(_selectedIndex + 1)),
                        onExit: _leaveGuidedMode,
                      )
                    : _RouteItinerarySheet(
                        trip: widget.trip,
                        route: _route,
                        pointKeys: _pointKeys,
                        selectedIndex: _selectedIndex,
                        scrollController: scrollController,
                        onStartGuided: _startGuidedMode,
                        onSelectPoint: (index) =>
                            unawaited(_selectPoint(index)),
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RouteItinerarySheet extends StatelessWidget {
  const _RouteItinerarySheet({
    required this.trip,
    required this.route,
    required this.pointKeys,
    required this.selectedIndex,
    required this.scrollController,
    required this.onStartGuided,
    required this.onSelectPoint,
  });

  final Trip trip;
  final TripRoute route;
  final List<GlobalKey> pointKeys;
  final int selectedIndex;
  final ScrollController scrollController;
  final VoidCallback onStartGuided;
  final ValueChanged<int> onSelectPoint;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      controller: scrollController,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.xs,
              AppSpacing.md,
              AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xxs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.greenSoft,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        trip.travelStyle,
                        style: const TextStyle(
                          color: AppColors.green,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Text(
                      '${trip.durationDays} days · ${route.points.length} points',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  trip.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    key: const ValueKey('start-guided-route'),
                    onPressed: onStartGuided,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start guided route'),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Itinerary',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xxl,
          ),
          sliver: SliverList.builder(
            itemCount: route.points.length,
            itemBuilder: (context, index) {
              final point = route.points[index];
              return Padding(
                key: pointKeys[index],
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _RoutePointCard(
                  point: point,
                  selected: selectedIndex == index,
                  onTap: () => onSelectPoint(index),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoutePointCard extends StatelessWidget {
  const _RoutePointCard({
    required this.point,
    required this.selected,
    required this.onTap,
  });

  final TripRoutePoint point;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      key: ValueKey('route-point-${point.index}'),
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: selected ? AppColors.terracottaSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? AppColors.terracotta : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _PointNumber(index: point.index, selected: selected),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _iconForPoint(point),
                          size: 15,
                          color: AppColors.terracotta,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Text(
                          point.isOrigin ? 'Departure' : point.type.label,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: AppColors.terracotta,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        if (point.isOptional) ...[
                          const SizedBox(width: AppSpacing.xs),
                          const Text(
                            'Optional',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      point.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      _pointMeta(point),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
                    ),
                    if (point.note != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        point.note!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                    if (point.coordinate == null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      const Row(
                        children: [
                          Icon(
                            Icons.location_off_outlined,
                            size: 15,
                            color: AppColors.muted,
                          ),
                          SizedBox(width: AppSpacing.xxs),
                          Text(
                            'Map location unavailable',
                            style: TextStyle(color: AppColors.muted),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GuidedRouteSheet extends StatelessWidget {
  const _GuidedRouteSheet({
    required this.trip,
    required this.point,
    required this.pointCount,
    required this.scrollController,
    required this.onPrevious,
    required this.onNext,
    required this.onExit,
  });

  final Trip trip;
  final TripRoutePoint point;
  final int pointCount;
  final ScrollController scrollController;
  final VoidCallback? onPrevious;
  final VoidCallback onNext;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final isLast = point.index == pointCount - 1;
    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xl,
      ),
      children: [
        const _SheetHandle(),
        Row(
          children: [
            Text(
              'Step ${point.index + 1}/$pointCount',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.terracotta,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            IconButton(
              key: const ValueKey('route-previous'),
              tooltip: 'Previous stop',
              onPressed: onPrevious,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            IconButton.filled(
              key: const ValueKey('route-next'),
              tooltip: isLast ? 'Finish route' : 'Next stop',
              onPressed: onNext,
              icon: Icon(
                isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Icon(_iconForPoint(point), color: AppColors.terracotta, size: 18),
            const SizedBox(width: AppSpacing.xs),
            Text(
              point.isOrigin ? 'Departure' : point.type.label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppColors.terracotta,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (point.isOptional) ...[
              const SizedBox(width: AppSpacing.xs),
              const Chip(label: Text('Optional')),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(point.name, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _pointMeta(point),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        if (point.note != null) ...[
          const SizedBox(height: AppSpacing.md),
          Text(point.note!, style: Theme.of(context).textTheme.bodyLarge),
        ],
        if (point.travelMode != null ||
            point.travelDurationMinutes != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.greenSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  _iconForTravelMode(point.travelMode),
                  color: AppColors.green,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    _travelDescription(point),
                    style: const TextStyle(
                      color: AppColors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        TextButton(
          key: const ValueKey('exit-guided-route'),
          onPressed: onExit,
          child: Text('Exit guided route · ${trip.title}'),
        ),
      ],
    );
  }
}

class _PointNumber extends StatelessWidget {
  const _PointNumber({required this.index, required this.selected});

  final int index;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.terracotta : AppColors.greenSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        '${index + 1}',
        style: TextStyle(
          color: selected ? Colors.white : AppColors.green,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 42,
        height: 4,
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.border,
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

class _MapActionButton extends StatelessWidget {
  const _MapActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 4,
      shadowColor: Colors.black26,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
      ),
    );
  }
}

String _pointMeta(TripRoutePoint point) {
  final values = <String>[formatTripDate(point.date)];
  if (point.travelMode != null) {
    values.add(point.travelMode!.label);
  }
  if (point.travelDurationMinutes != null) {
    values.add(_formatDuration(point.travelDurationMinutes!));
  }
  return values.join(' · ');
}

String _travelDescription(TripRoutePoint point) {
  final mode = point.travelMode?.label ?? 'Transfer';
  final duration = point.travelDurationMinutes;
  return duration == null ? mode : '$mode · about ${_formatDuration(duration)}';
}

String _formatDuration(int minutes) {
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m';
}

IconData _iconForPoint(TripRoutePoint point) {
  if (point.isOrigin) {
    return Icons.trip_origin_rounded;
  }
  return switch (point.type) {
    TripStopType.waypoint => Icons.location_on_outlined,
    TripStopType.activity => Icons.directions_walk_rounded,
    TripStopType.overnight => Icons.bed_outlined,
    TripStopType.breakStop => Icons.local_cafe_outlined,
  };
}

IconData _iconForTravelMode(TripTravelMode? mode) => switch (mode) {
  TripTravelMode.drive => Icons.directions_car_outlined,
  TripTravelMode.sharedTaxi => Icons.local_taxi_outlined,
  TripTravelMode.train => Icons.train_outlined,
  TripTravelMode.bus => Icons.directions_bus_outlined,
  TripTravelMode.walk => Icons.directions_walk_rounded,
  TripTravelMode.other || null => Icons.route_outlined,
};
