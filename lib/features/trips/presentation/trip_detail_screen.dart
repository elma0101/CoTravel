import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../join_requests/presentation/join_request_panel.dart';
import '../../join_requests/domain/trip_join_request.dart';
import '../../profile/domain/traveler_action_target.dart';
import '../../profile/presentation/traveler_action_sheet.dart';
import '../../safety/domain/safety_models.dart';
import '../../safety/presentation/safety_actions.dart';
import '../domain/trip.dart';
import '../domain/trip_route.dart';
import 'trip_formatters.dart';
import 'widgets/mountain_illustration.dart';
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
            appBar: AppBar(title: Text(tr('Trip details'))),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final trip = snapshot.data;
        if (trip == null) {
          return Scaffold(
            appBar: AppBar(title: Text(tr('Trip details'))),
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
        return ListenableBuilder(
          listenable: catalog,
          builder: (context, child) {
            final current = catalog.tripById(widget.tripId) ?? trip;
            return Scaffold(
              appBar: AppBar(
                title: Text(tr('Trip details')),
                actions: [_SaveTripButton(trip: current)],
              ),
              body: _TripDetails(trip: current),
              bottomNavigationBar: JoinRequestBar(trip: current),
            );
          },
        );
      },
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}

class _SaveTripButton extends ConsumerWidget {
  const _SaveTripButton({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(tripCatalogProvider);
    final saved = catalog.isSaved(trip.id);
    return IconButton(
      key: const ValueKey('save-trip'),
      tooltip: saved ? tr('Remove from saved') : tr('Save trip'),
      isSelected: saved,
      icon: Icon(
        saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
      ),
      onPressed: () async {
        try {
          await catalog.toggleSaved(trip);
        } on Object {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(tr('Your saved trips could not be updated.')),
              ),
            );
          }
        }
      },
    );
  }
}

class _TripDetails extends StatelessWidget {
  const _TripDetails({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final route = TripRoute.fromTrip(trip);
    final textTheme = Theme.of(context).textTheme;

    return ListView(
      key: ValueKey('trip-details-${trip.id}'),
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      children: [
        _TripHero(trip: trip),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trip.title, style: textTheme.headlineMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatTripDateRange(trip.startDate, trip.endDate)} · ${tr(trip.travelStyle)}',
                style: textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: _HostRow(trip: trip)),
        const SizedBox(height: AppSpacing.sm),
        _DetailSection(child: _VerificationChip(verified: trip.hostVerified)),
        const SizedBox(height: AppSpacing.lg),
        _DetailSection(child: Text(trip.summary, style: textTheme.bodyLarge)),
        const SizedBox(height: AppSpacing.lg),
        _DetailSection(
          child: _RouteSection(trip: trip, route: route),
        ),
        const SizedBox(height: AppSpacing.lg),
        _DetailSection(child: _CostTable(trip: trip)),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: _LogisticsAccessCard(trip: trip)),
        const SizedBox(height: AppSpacing.md),
        _DetailSection(child: JoinRequestPanel(trip: trip)),
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
      height: 190,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo == null)
            const MountainIllustration()
          else ...[
            Semantics(
              image: true,
              label: tr(photo.semanticLabel),
              child: Image.asset(
                photo.assetPath,
                alignment: photo.alignment,
                fit: BoxFit.cover,
                cacheWidth: 1600,
                excludeFromSemantics: true,
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              right: AppSpacing.sm,
              child: TripPhotoAttributionButton(photo: photo),
            ),
          ],
        ],
      ),
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
                          ? tr('Shared logistics')
                          : tr('Private group logistics'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      hasAccess
                          ? tr(
                              'Calculate each share and open the booking shortlist.',
                            )
                          : tr(
                              'Links unlock after both sides confirm the trip.',
                            ),
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
                  tooltip: tr('Open shared logistics'),
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

class _HostRow extends ConsumerWidget {
  const _HostRow({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: chat,
      builder: (context, child) {
        final conversation = chat.conversationForTrip(trip.id);
        return InkWell(
          key: ValueKey('host-actions-${trip.hostId}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => showTravelerActions(
            context,
            target: TravelerActionTarget(
              userId: trip.hostId,
              displayName: trip.hostName,
              homeCity: trip.hostHomeCity,
              isVerified: trip.hostVerified,
              tripId: trip.id,
              tripTitle: trip.title,
              conversationId: conversation?.id,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.terracottaSoft,
                  foregroundColor: AppColors.ink,
                  child: Text(
                    _initials(trip.hostName),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Hosted by {hostName}', {'hostName': trip.hostName}),
                        style: textTheme.titleMedium,
                      ),
                      Text(
                        [
                          ?trip.hostOccupation,
                          ?trip.hostHomeCity,
                        ].join(' · ').ifEmpty(tr('CoTravel member')),
                        style: textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  tr('View'),
                  style: TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
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

class _VerificationChip extends StatelessWidget {
  const _VerificationChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    final color = verified ? AppColors.green : AppColors.muted;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xxs,
        ),
        decoration: BoxDecoration(
          color: verified ? AppColors.greenSoft : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              verified ? Icons.verified_outlined : Icons.hourglass_top_rounded,
              size: 15,
              color: color,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Text(
              verified ? tr('LinkedIn verified') : tr('Not verified yet'),
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RouteSection extends StatelessWidget {
  const _RouteSection({required this.trip, required this.route});

  final Trip trip;
  final TripRoute route;

  @override
  Widget build(BuildContext context) {
    final count = route.points.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Route'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${trPlural(count, '{n} stop', '{n} stops')} · ${trPlural(trip.durationDays, '{n} day', '{n} days')}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        for (var index = 0; index < count; index++)
          _RoutePointRow(
            point: route.points[index],
            isLast: index == count - 1,
          ),
        if (route.canExplore)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('explore-trip-route'),
              onPressed: () => context.push(AppRoutes.tripRoute(trip.id)),
              icon: const Icon(Icons.map_outlined, size: 18),
              label: Text(tr('View on map')),
            ),
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
    final textTheme = Theme.of(context).textTheme;
    final details = [
      formatTripDate(point.date),
      if (point.travelMode != null || point.travelDurationMinutes != null)
        _travelMeta(point),
      if (point.note != null && !point.isOrigin) point.note!,
    ].join(' · ');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 20,
            child: Column(
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 9,
                  height: 9,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 1.5, color: AppColors.border),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(point.name, style: textTheme.titleMedium),
                  Text(
                    details,
                    style: textTheme.bodyMedium?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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

class _CostTable extends StatelessWidget {
  const _CostTable({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tr('Estimated cost per traveler'), style: textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _CostRow(
            label: tr('Accommodation'),
            value: formatTripMoney(
              trip.lodgingTotal / trip.capacity,
              trip.currency,
            ),
          ),
          const Divider(height: AppSpacing.md),
          _CostRow(
            label: tr('Shared transport'),
            value: formatTripMoney(
              trip.transportTotal / trip.capacity,
              trip.currency,
            ),
          ),
          const Divider(height: AppSpacing.md),
          _CostRow(
            label: tr('Total'),
            value: formatTripMoney(trip.estimatedFullGroupShare, trip.currency),
            emphasized: true,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            tr(
              'With a full group of {capacity}. Planning estimate only. The group confirms every booking before paying.',
              {'capacity': trip.capacity},
            ),
            style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _CostRow extends StatelessWidget {
  const _CostRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final weight = emphasized ? FontWeight.w600 : FontWeight.w400;
    return Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: weight)),
        ),
        Text(value, style: TextStyle(fontWeight: weight)),
      ],
    );
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
              tr('This trip is unavailable'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(tr('It may have been closed or removed by its host.')),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: onRetry, child: Text(tr('Try again'))),
          ],
        ),
      ),
    );
  }
}
