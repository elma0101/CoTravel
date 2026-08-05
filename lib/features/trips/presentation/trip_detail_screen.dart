import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../join_requests/presentation/join_request_panel.dart';
import '../../join_requests/domain/trip_join_request.dart';
import '../../safety/domain/safety_models.dart';
import '../../safety/presentation/safety_actions.dart';
import '../domain/trip.dart';
import '../domain/trip_route.dart';
import 'trip_formatters.dart';
import 'widgets/trip_cover_images.dart';
import 'widgets/trip_photo_attribution.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  const TripDetailScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
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
          return Scaffold(
            appBar: AppBar(title: const Text('Trip details')),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final trip = snapshot.data;
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Trip details')),
            body: _MissingTrip(
              onRetry: () {
                setState(() {
                  _trip = ref.read(tripCatalogProvider).findTrip(widget.tripId);
                });
              },
            ),
          );
        }
        final catalog = ref.watch(tripCatalogProvider);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Trip details'),
            backgroundColor: AppColors.green,
            foregroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
          ),
          body: ListenableBuilder(
            listenable: catalog,
            builder: (context, child) {
              return _TripDetails(
                trip: catalog.tripById(widget.tripId) ?? trip,
              );
            },
          ),
        );
      },
    );
  }
}

class _TripDetails extends ConsumerWidget {
  const _TripDetails({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final route = TripRoute.fromTrip(trip);
    final onExplore = route.canExplore
        ? () => context.push(AppRoutes.tripRoute(trip.id))
        : null;

    return ListView(
      key: ValueKey('trip-details-${trip.id}'),
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        _TripHero(trip: trip),
        Transform.translate(
          offset: const Offset(0, -30),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: _TripFactsPanel(trip: trip),
          ),
        ),
        _DetailSection(child: _EditorialPlan(trip: trip)),
        const SizedBox(height: AppSpacing.xxl),
        _DetailSection(
          child: _SectionTitle(
            eyebrow: 'ITINERARY',
            title: 'Route',
            subtitle:
                '${route.points.length} places · ${trip.durationDays} days',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(
          child: _RouteMapPreview(
            trip: trip,
            pointCount: route.points.length,
            onExplore: onExplore,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _DetailSection(child: _RouteTimeline(route: route)),
        const SizedBox(height: AppSpacing.xxl),
        const _DetailSection(
          child: _SectionTitle(
            eyebrow: 'GROUP ESTIMATE',
            title: 'Estimated shared costs',
            subtitle: 'A clear starting point before anyone books.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: _CostBreakdown(trip: trip)),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: _LogisticsAccessCard(trip: trip)),
        const SizedBox(height: AppSpacing.xxl),
        const _DetailSection(
          child: _SectionTitle(
            eyebrow: 'TRAVEL TOGETHER',
            title: 'Your host',
            subtitle: 'A little context before you request to join.',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: _HostCard(trip: trip)),
        const SizedBox(height: AppSpacing.sm),
        _DetailSection(
          child: SafetyOptionsButton(
            target: SafetyTarget(
              userId: trip.hostId,
              userName: trip.hostName,
              tripId: trip.id,
              tripTitle: trip.title,
            ),
            onBlocked: () => context.pop(),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _DetailSection(child: JoinRequestPanel(trip: trip)),
      ],
    );
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: child,
    );
  }
}

class _TripHero extends StatelessWidget {
  const _TripHero({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final photo = TripCoverImages.forTrip(trip);
    return SizedBox(
      height: 320,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _TripHeroBackground(trip: trip, photo: photo),
          if (photo != null)
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: TripPhotoAttributionButton(photo: photo),
            ),
        ],
      ),
    );
  }
}

class _TripHeroBackground extends StatelessWidget {
  const _TripHeroBackground({required this.trip, required this.photo});

  final Trip trip;
  final TripCoverPhoto? photo;

  @override
  Widget build(BuildContext context) {
    final photo = this.photo;
    return Semantics(
      image: photo != null,
      label: photo?.semanticLabel,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null)
            Image.asset(
              photo.assetPath,
              alignment: photo.alignment,
              fit: BoxFit.cover,
              cacheWidth: 1600,
              excludeFromSemantics: true,
            )
          else
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.green, Color(0xFF497667)],
                ),
              ),
            ),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black38, Colors.transparent, Colors.black87],
                stops: [0, 0.42, 1],
              ),
            ),
          ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: 58,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.terracotta,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    trip.travelStyle.toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  trip.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    height: 1.03,
                    shadows: const [
                      Shadow(color: Colors.black54, blurRadius: 10),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Row(
                  children: [
                    const Icon(
                      Icons.route_rounded,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    const Text(
                      'Route',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Container(
                      width: 3,
                      height: 3,
                      decoration: const BoxDecoration(
                        color: Colors.white70,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        '${trip.originCity} to ${trip.destinationCity}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 7),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditorialPlan extends StatelessWidget {
  const _EditorialPlan({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'THE PLAN',
          style: TextStyle(
            color: AppColors.terracotta,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 3,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.terracotta,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                trip.summary,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  height: 1.42,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LogisticsAccessCard extends ConsumerWidget {
  const _LogisticsAccessCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(appAuthStateProvider).profile?.id;
    final requests = ref.watch(joinRequestControllerProvider);
    return ListenableBuilder(
      listenable: requests,
      builder: (context, child) {
        final request = requests.requestForTrip(trip.id);
        final hasAccess =
            trip.hostId == userId ||
            request?.status == JoinRequestStatus.confirmed;
        return Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: hasAccess
                    ? AppColors.terracottaSoft
                    : AppColors.greenSoft,
                foregroundColor: hasAccess
                    ? AppColors.terracotta
                    : AppColors.green,
                child: Icon(
                  hasAccess
                      ? Icons.calculate_outlined
                      : Icons.lock_outline_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasAccess
                          ? 'Shared logistics'
                          : 'Private group logistics',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      hasAccess
                          ? 'Calculate each share and open the booking shortlist.'
                          : 'Links unlock after both sides confirm the trip.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              if (hasAccess)
                IconButton(
                  key: const ValueKey('open-shared-logistics'),
                  tooltip: 'Open shared logistics',
                  onPressed: () =>
                      context.push(AppRoutes.tripLogistics(trip.id)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TripFactsPanel extends StatelessWidget {
  const _TripFactsPanel({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      elevation: 8,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Expanded(
              child: _DetailFact(
                icon: Icons.calendar_today_outlined,
                value: formatTripDate(trip.startDate),
                label: '${trip.durationDays} days',
              ),
            ),
            const SizedBox(height: 54, child: VerticalDivider(width: 20)),
            Expanded(
              child: _DetailFact(
                icon: Icons.event_seat_outlined,
                value:
                    '${trip.openSeats} ${trip.openSeats == 1 ? 'place' : 'places'} left',
                label: 'of ${trip.capacity}',
              ),
            ),
            const SizedBox(height: 54, child: VerticalDivider(width: 20)),
            Expanded(
              child: _DetailFact(
                icon: Icons.payments_outlined,
                value: formatTripMoney(
                  trip.estimatedFullGroupShare,
                  trip.currency,
                ),
                label: 'per person',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailFact extends StatelessWidget {
  const _DetailFact({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.terracotta, size: 19),
        const SizedBox(height: AppSpacing.xs),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        Text(
          label,
          maxLines: 1,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
  });

  final String eyebrow;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: AppColors.terracotta,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _RouteMapPreview extends StatelessWidget {
  const _RouteMapPreview({
    required this.trip,
    required this.pointCount,
    required this.onExplore,
  });

  final Trip trip;
  final int pointCount;
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.greenSoft,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('explore-trip-route'),
        onTap: onExplore,
        child: SizedBox(
          height: 184,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(painter: _RoutePreviewPainter(pointCount)),
              Positioned(
                top: AppSpacing.md,
                left: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.map_outlined,
                        size: 15,
                        color: AppColors.green,
                      ),
                      SizedBox(width: AppSpacing.xxs),
                      Text(
                        'INTERACTIVE ROUTE',
                        style: TextStyle(
                          color: AppColors.green,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                left: AppSpacing.md,
                right: AppSpacing.md,
                bottom: AppSpacing.md,
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: AppColors.surface.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${trip.originCity} → ${trip.destinationCity}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              onExplore == null
                                  ? 'Map coordinates unavailable'
                                  : 'Tap to explore every stop',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.muted),
                            ),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: onExplore == null
                            ? AppColors.border
                            : AppColors.green,
                        foregroundColor: Colors.white,
                        child: Icon(
                          onExplore == null
                              ? Icons.location_off_outlined
                              : Icons.arrow_outward_rounded,
                          size: 20,
                        ),
                      ),
                    ],
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

class _RoutePreviewPainter extends CustomPainter {
  const _RoutePreviewPainter(this.pointCount);

  final int pointCount;

  @override
  void paint(Canvas canvas, Size size) {
    final contourPaint = Paint()
      ..color = AppColors.green.withValues(alpha: 0.1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.12, size.height * 0.2),
        width: size.width * 0.58,
        height: size.height * 0.54,
      ),
      contourPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.86, size.height * 0.22),
        width: size.width * 0.72,
        height: size.height * 0.64,
      ),
      contourPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(size.width * 0.46, size.height * 0.72),
        width: size.width * 0.9,
        height: size.height * 0.48,
      ),
      contourPaint,
    );

    final route = Path()
      ..moveTo(size.width * 0.08, size.height * 0.68)
      ..cubicTo(
        size.width * 0.24,
        size.height * 0.2,
        size.width * 0.46,
        size.height * 0.77,
        size.width * 0.61,
        size.height * 0.34,
      )
      ..cubicTo(
        size.width * 0.72,
        size.height * 0.08,
        size.width * 0.82,
        size.height * 0.46,
        size.width * 0.92,
        size.height * 0.2,
      );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.surface.withValues(alpha: 0.95)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      route,
      Paint()
        ..color = AppColors.terracotta
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );

    final metric = route.computeMetrics().first;
    final markerCount = pointCount < 2
        ? 2
        : pointCount > 8
        ? 8
        : pointCount;
    for (var index = 0; index < markerCount; index++) {
      final offset = metric.length * index / (markerCount - 1);
      final position = metric.getTangentForOffset(offset)!.position;
      canvas.drawCircle(position, 9, Paint()..color = AppColors.surface);
      canvas.drawCircle(
        position,
        6.5,
        Paint()
          ..color = index == markerCount - 1
              ? AppColors.terracotta
              : AppColors.green,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${index + 1}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w800,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, position - Offset(label.width / 2, label.height / 2));
    }
  }

  @override
  bool shouldRepaint(_RoutePreviewPainter oldDelegate) {
    return pointCount != oldDelegate.pointCount;
  }
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({required this.route});

  final TripRoute route;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var index = 0; index < route.points.length; index++)
          _RoutePointRow(
            point: route.points[index],
            isLast: index == route.points.length - 1,
          ),
      ],
    );
  }
}

class _RoutePointRow extends StatelessWidget {
  const _RoutePointRow({required this.point, required this.isLast});

  final TripRoutePoint point;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isLast ? AppColors.terracotta : AppColors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surface, width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 5),
                  ],
                ),
                child: Text(
                  '${point.index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: point.note == null ? 58 : 78,
                  color: AppColors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              bottom: AppSpacing.md,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.isOrigin ? 'DEPARTURE' : point.type.label.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.terracotta,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        point.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    Text(
                      formatTripDate(point.date),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
                if (point.travelMode != null ||
                    point.travelDurationMinutes != null) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    _travelMeta(point),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if (point.note != null && !point.isOrigin) ...[
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    point.note!,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

String _travelMeta(TripRoutePoint point) {
  final values = <String>[];
  if (point.travelMode != null) {
    values.add(point.travelMode!.label);
  }
  final minutes = point.travelDurationMinutes;
  if (minutes != null) {
    if (minutes < 60) {
      values.add('$minutes min');
    } else {
      final hours = minutes ~/ 60;
      final remainder = minutes % 60;
      values.add(remainder == 0 ? '${hours}h' : '${hours}h ${remainder}m');
    }
  }
  return values.join(' · ');
}

class _CostBreakdown extends StatelessWidget {
  const _CostBreakdown({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    var lodgingFlex = trip.totalCost <= 0
        ? 50
        : (trip.lodgingTotal / trip.totalCost * 100).round();
    if (lodgingFlex < 4) lodgingFlex = 4;
    if (lodgingFlex > 96) lodgingFlex = 96;
    final transportFlex = 100 - lodgingFlex;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ESTIMATED EACH',
            style: TextStyle(
              color: AppColors.green,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            formatTripMoney(trip.estimatedFullGroupShare, trip.currency),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: AppColors.green,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'with a full group of ${trip.capacity}',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.lg),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: lodgingFlex,
                    child: const ColoredBox(color: AppColors.green),
                  ),
                  Expanded(
                    flex: transportFlex,
                    child: const ColoredBox(color: AppColors.terracotta),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          _CostLegend(
            color: AppColors.green,
            label: 'Lodging',
            value: formatTripMoney(trip.lodgingTotal, trip.currency),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CostLegend(
            color: AppColors.terracotta,
            label: 'Transport',
            value: formatTripMoney(trip.transportTotal, trip.currency),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(color: AppColors.border),
          ),
          Text(
            'Planning estimate only. The group confirms every booking before paying.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CostLegend extends StatelessWidget {
  const _CostLegend({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.terracottaSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 64,
                height: 64,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(trip.hostName),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.hostName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      trip.hostHomeCity ?? 'CoTravel member',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      trip.hostVerified
                          ? Icons.verified_rounded
                          : Icons.hourglass_top_rounded,
                      color: trip.hostVerified
                          ? AppColors.green
                          : AppColors.muted,
                      size: 16,
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                    Text(
                      trip.hostVerified ? 'Verified' : 'Pending',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(color: AppColors.border),
          ),
          Text(
            'Hosting a ${trip.travelStyle.toLowerCase()} trip for a small group of up to ${trip.capacity} travelers.',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
          ),
        ],
      ),
    );
  }

  String _initials(String value) {
    return value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();
  }
}

class _MissingTrip extends StatelessWidget {
  const _MissingTrip({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.route_outlined, size: 44, color: AppColors.green),
            const SizedBox(height: AppSpacing.md),
            Text(
              'This trip is unavailable',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text('It may have been closed or removed by its host.'),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
