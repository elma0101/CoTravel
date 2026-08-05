import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/screen_header.dart';
import '../../join_requests/domain/trip_join_request.dart';
import '../application/trip_catalog_controller.dart';
import 'trip_formatters.dart';
import 'widgets/trip_card.dart';

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen> {
  int _selectedView = 0;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);
    final requests = ref.watch(joinRequestControllerProvider);

    return SafeArea(
      child: ListenableBuilder(
        listenable: catalog,
        builder: (context, child) {
          return ListenableBuilder(
            listenable: requests,
            builder: (context, child) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const ScreenHeader(
                    title: 'My trips',
                    subtitle: 'Host thoughtfully and keep requests visible.',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: SegmentedButton<int>(
                      segments: [
                        const ButtonSegment(
                          value: 0,
                          icon: Icon(Icons.route_outlined),
                          label: Text('Hosting'),
                        ),
                        ButtonSegment(
                          value: 1,
                          icon: const Icon(Icons.handshake_outlined),
                          label: Text(
                            requests.travelerRequests.isEmpty
                                ? 'Requests'
                                : 'Requests ${requests.travelerRequests.length}',
                          ),
                        ),
                      ],
                      selected: {_selectedView},
                      onSelectionChanged: (selection) {
                        setState(() => _selectedView = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_selectedView == 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.md,
                      ),
                      child: FilledButton.icon(
                        key: const ValueKey('plan-trip'),
                        onPressed: () => context.push(AppRoutes.createTrip),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Plan a new trip'),
                      ),
                    ),
                  Expanded(
                    child: _selectedView == 0
                        ? _HostedTripsView(
                            catalog: catalog,
                            requests: requests.hostRequests,
                          )
                        : _TravelerRequestsView(
                            requests: requests.travelerRequests,
                            isLoading: requests.isLoading,
                            onRefresh: requests.load,
                          ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _HostedTripsView extends StatelessWidget {
  const _HostedTripsView({required this.catalog, required this.requests});

  final TripCatalogController catalog;
  final List<TripJoinRequest> requests;

  @override
  Widget build(BuildContext context) {
    final trips = catalog.hostedTrips;
    if (catalog.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (trips.isEmpty) {
      return const EmptyState(
        icon: Icons.luggage_outlined,
        title: 'No trips yet',
        message:
            'Create your first itinerary. A clear route and honest budget are enough to begin.',
      );
    }
    return RefreshIndicator(
      onRefresh: catalog.load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        itemCount: trips.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.md),
        itemBuilder: (context, index) {
          final trip = trips[index];
          final pending = requests
              .where(
                (request) =>
                    request.tripId == trip.id &&
                    request.status == JoinRequestStatus.pendingHost,
              )
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (pending > 0) ...[
                _PendingRequestBanner(
                  count: pending,
                  onTap: () => context.push(AppRoutes.tripRequests(trip.id)),
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              TripCard(
                trip: trip,
                onTap: () => context.push(AppRoutes.tripDetails(trip.id)),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PendingRequestBanner extends StatelessWidget {
  const _PendingRequestBanner({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.terracottaSoft,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: const ValueKey('pending-host-requests'),
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(
                Icons.person_search_outlined,
                color: AppColors.terracotta,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '$count new ${count == 1 ? 'request' : 'requests'} to review',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TravelerRequestsView extends StatelessWidget {
  const _TravelerRequestsView({
    required this.requests,
    required this.isLoading,
    required this.onRefresh,
  });

  final List<TripJoinRequest> requests;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (requests.isEmpty) {
      return const EmptyState(
        icon: Icons.handshake_outlined,
        title: 'No join requests',
        message:
            'When a trip feels right, introduce yourself to the host from its detail page.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.xs,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        itemCount: requests.length,
        separatorBuilder: (context, index) =>
            const SizedBox(height: AppSpacing.sm),
        itemBuilder: (context, index) {
          final request = requests[index];
          return _TravelerRequestCard(
            request: request,
            onTap: () => context.push(AppRoutes.tripDetails(request.tripId)),
          );
        },
      ),
    );
  }
}

class _TravelerRequestCard extends StatelessWidget {
  const _TravelerRequestCard({required this.request, required this.onTap});

  final TripJoinRequest request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = switch (request.status) {
      JoinRequestStatus.pendingHost => AppColors.terracotta,
      JoinRequestStatus.pendingTraveler ||
      JoinRequestStatus.confirmed => AppColors.green,
      JoinRequestStatus.declined ||
      JoinRequestStatus.withdrawn => AppColors.muted,
    };
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.border),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  request.status == JoinRequestStatus.confirmed
                      ? Icons.check_rounded
                      : Icons.handshake_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.tripTitle,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '${request.routeLabel} · ${formatTripDate(request.startDate)}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      request.status.label,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
