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
    return Scaffold(
      appBar: AppBar(title: const Text('Trip details')),
      body: FutureBuilder<Trip?>(
        future: _trip,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final trip = snapshot.data;
          if (trip == null) {
            return _MissingTrip(
              onRetry: () {
                setState(() {
                  _trip = ref.read(tripCatalogProvider).findTrip(widget.tripId);
                });
              },
            );
          }
          final catalog = ref.watch(tripCatalogProvider);
          return ListenableBuilder(
            listenable: catalog,
            builder: (context, child) {
              return _TripDetails(
                trip: catalog.tripById(widget.tripId) ?? trip,
              );
            },
          );
        },
      ),
    );
  }
}

class _TripDetails extends ConsumerWidget {
  const _TripDetails({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        120,
      ),
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: AppColors.greenSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                trip.travelStyle,
                style: const TextStyle(
                  color: AppColors.green,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Spacer(),
            Text(
              '${trip.openSeats} open ${trip.openSeats == 1 ? 'seat' : 'seats'}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Text(trip.title, style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.sm),
        Text(
          '${trip.originCity} to ${trip.destinationCity}',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.lg),
        _FactsRow(trip: trip),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'Route'),
        const SizedBox(height: AppSpacing.md),
        _RouteTimeline(
          trip: trip,
          onExplore: TripRoute.fromTrip(trip).canExplore
              ? () => context.push(AppRoutes.tripRoute(trip.id))
              : null,
        ),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'The plan'),
        const SizedBox(height: AppSpacing.sm),
        Text(trip.summary, style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'Estimated shared costs'),
        const SizedBox(height: AppSpacing.md),
        _CostBreakdown(trip: trip),
        const SizedBox(height: AppSpacing.md),
        _LogisticsAccessCard(trip: trip),
        const SizedBox(height: AppSpacing.xl),
        const _SectionTitle(title: 'Your host'),
        const SizedBox(height: AppSpacing.md),
        _HostCard(trip: trip),
        SafetyOptionsButton(
          target: SafetyTarget(
            userId: trip.hostId,
            userName: trip.hostName,
            tripId: trip.id,
            tripTitle: trip.title,
          ),
          onBlocked: () => context.pop(),
        ),
        const SizedBox(height: AppSpacing.xl),
        JoinRequestPanel(trip: trip),
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

class _FactsRow extends StatelessWidget {
  const _FactsRow({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: _Fact(
              icon: Icons.calendar_today_outlined,
              value: formatTripDateRange(trip.startDate, trip.endDate),
              label: '${trip.durationDays} days',
            ),
          ),
          const SizedBox(height: 54, child: VerticalDivider()),
          Expanded(
            child: _Fact(
              icon: Icons.group_outlined,
              value: '${trip.capacity} people',
              label: '${trip.openSeats} places left',
            ),
          ),
        ],
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: AppColors.green, size: 20),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(title, style: Theme.of(context).textTheme.titleLarge);
  }
}

class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({required this.trip, required this.onExplore});

  final Trip trip;
  final VoidCallback? onExplore;

  @override
  Widget build(BuildContext context) {
    final points = [
      _RoutePoint(
        city: trip.originCity,
        date: trip.startDate,
        note: 'Departure',
      ),
      ...trip.stops.map(
        (stop) => _RoutePoint(
          city: stop.city,
          date: stop.arrivalDate,
          note: stop.notes,
        ),
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          for (var index = 0; index < points.length; index++)
            _RoutePointRow(
              point: points[index],
              isLast: index == points.length - 1,
            ),
          const SizedBox(height: AppSpacing.xs),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('explore-trip-route'),
              onPressed: onExplore,
              icon: const Icon(Icons.map_outlined),
              label: Text(
                onExplore == null
                    ? 'Map coordinates unavailable'
                    : 'Explore this route',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePoint {
  const _RoutePoint({required this.city, required this.date, this.note});

  final String city;
  final DateTime date;
  final String? note;
}

class _RoutePointRow extends StatelessWidget {
  const _RoutePointRow({required this.point, required this.isLast});

  final _RoutePoint point;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 28,
          child: Column(
            children: [
              Icon(
                isLast
                    ? Icons.location_on_rounded
                    : Icons.radio_button_checked_rounded,
                color: isLast ? AppColors.terracotta : AppColors.green,
                size: isLast ? 22 : 17,
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: point.note == null ? 42 : 64,
                  color: AppColors.border,
                ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        point.city,
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
                if (point.note != null) ...[
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

class _CostBreakdown extends StatelessWidget {
  const _CostBreakdown({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _CostLine(
            label: 'Lodging',
            value: formatTripMoney(trip.lodgingTotal, trip.currency),
          ),
          const SizedBox(height: AppSpacing.xs),
          _CostLine(
            label: 'Transport',
            value: formatTripMoney(trip.transportTotal, trip.currency),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Divider(color: AppColors.green),
          ),
          _CostLine(
            label: 'Estimated each with a full group',
            value: formatTripMoney(trip.estimatedFullGroupShare, trip.currency),
            emphasized: true,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Based on ${trip.capacity} people. Prices are planning estimates, not bookings.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CostLine extends StatelessWidget {
  const _CostLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: AppColors.terracottaSoft,
            foregroundColor: AppColors.terracotta,
            child: Text(_initials(trip.hostName)),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.hostName,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  trip.hostHomeCity ?? 'CoTravel member',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          Icon(
            trip.hostVerified
                ? Icons.verified_rounded
                : Icons.person_outline_rounded,
            color: trip.hostVerified ? AppColors.green : AppColors.muted,
            semanticLabel: trip.hostVerified ? 'Verified host' : 'Host',
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
