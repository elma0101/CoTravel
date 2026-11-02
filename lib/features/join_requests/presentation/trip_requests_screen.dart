import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../application/join_request_controller.dart';
import '../../trips/domain/trip.dart';
import '../domain/trip_join_request.dart';

class TripRequestsScreen extends ConsumerWidget {
  const TripRequestsScreen({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(joinRequestControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(tr('Traveler requests'))),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, child) {
            if (controller.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }
            final requests = controller.hostRequestsForTrip(tripId);
            if (requests.isEmpty) {
              return const _EmptyRequests();
            }
            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              itemCount: requests.length + 1,
              separatorBuilder: (context, index) =>
                  const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, index) {
                if (index == 0) {
                  return _RequestsIntro(request: requests.first);
                }
                final request = requests[index - 1];
                return _CandidateCard(
                  request: request,
                  trip: ref.watch(tripCatalogProvider).tripById(request.tripId),
                  isUpdating: controller.isUpdating(request.id),
                  onAccept: () =>
                      _review(context, controller, request, accept: true),
                  onDecline: () =>
                      _confirmDecline(context, controller, request),
                );
              },
            );
          },
        ),
      ),
    );
  }

  Future<void> _confirmDecline(
    BuildContext context,
    JoinRequestController controller,
    TripJoinRequest request,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Decline this request?')),
        content: Text(
          tr('{travelerName} will see that the request was not accepted.', {
            'travelerName': request.travelerName,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Keep reviewing')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Decline')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _review(context, controller, request, accept: false);
    }
  }

  Future<void> _review(
    BuildContext context,
    JoinRequestController controller,
    TripJoinRequest request, {
    required bool accept,
  }) async {
    try {
      await controller.reviewAsHost(request, accept: accept);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? tr('Approved. {travelerName} must now confirm.', {
                      'travelerName': request.travelerName,
                    })
                  : tr('Request declined.'),
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.errorMessage ?? tr('Request could not be updated.'),
            ),
          ),
        );
      }
    }
  }
}

class _RequestsIntro extends StatelessWidget {
  const _RequestsIntro({required this.request});

  final TripJoinRequest request;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          request.tripTitle,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          '${request.routeLabel} · ${formatTripDate(request.startDate)}',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          tr(
            'Review the traveler’s profile and note. Approval invites them to confirm; it does not lock a seat yet.',
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

/// The mockup's "Useful context". Declared answers are labelled as such, and
/// cost shares assume an equal split.
class _UsefulContext extends StatelessWidget {
  const _UsefulContext({required this.request, required this.trip});

  final TripJoinRequest request;
  final Trip? trip;

  @override
  Widget build(BuildContext context) {
    final trip = this.trip;
    final languages = request.travelerLanguages;
    final canCompareCost =
        trip != null &&
        request.status == JoinRequestStatus.pendingHost &&
        trip.openSeats > 0;
    final rows = <Widget>[
      if (request.availableAllDates != null)
        _ContextRow(
          icon: Icons.event_available_outlined,
          title: request.availableAllDates!
              ? tr('Free for all the dates')
              : tr('Dates to discuss'),
        ),
      if (request.budgetFits != null)
        _ContextRow(
          icon: Icons.savings_outlined,
          title: request.budgetFits!
              ? tr('Budget works for them')
              : tr('Budget to discuss'),
        ),
      if (languages.isNotEmpty)
        _ContextRow(icon: Icons.translate, title: languages.join(', ')),
      if (request.canShareDriving == true)
        _ContextRow(
          icon: Icons.directions_car_outlined,
          title: tr('Can share driving'),
          subtitle: tr('Driving licence not checked'),
        ),
    ];
    if (rows.isEmpty && !canCompareCost) {
      return const SizedBox.shrink();
    }
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(tr('Useful context'), style: textTheme.titleSmall),
              ),
              Text(
                tr('Declared by the traveler'),
                style: textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          ...rows,
          if (canCompareCost) ...[
            const SizedBox(height: AppSpacing.xs),
            _CostLine(
              label: tr('Current group cost'),
              value: formatTripMoney(trip.currentGroupShare, trip.currency),
            ),
            const Divider(height: AppSpacing.md),
            _CostLine(
              key: const ValueKey('cost-if-joins'),
              label: tr('If {name} joins', {'name': request.travelerName}),
              value: formatTripMoney(
                trip.totalCost / (trip.participantCount + 1),
                trip.currency,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContextRow extends StatelessWidget {
  const _ContextRow({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.muted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: textTheme.bodyMedium),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: textTheme.bodySmall?.copyWith(
                      color: AppColors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CostLine extends StatelessWidget {
  const _CostLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(
          tr('{amount} each', {'amount': value}),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.request,
    required this.trip,
    required this.isUpdating,
    required this.onAccept,
    required this.onDecline,
  });

  final TripJoinRequest request;
  final Trip? trip;
  final bool isUpdating;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: AppColors.greenSoft,
                foregroundColor: AppColors.green,
                child: Text(_initials(request.travelerName)),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            request.travelerName,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        if (request.travelerVerified) ...[
                          const SizedBox(width: AppSpacing.xxs),
                          const Icon(
                            Icons.verified_rounded,
                            color: AppColors.green,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                    Text(
                      request.travelerHomeCity ?? tr('CoTravel traveler'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: request.status),
            ],
          ),
          if (request.travelerBio != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              request.travelerBio!,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.canvas,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              request.message,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _UsefulContext(request: request, trip: trip),
          if (request.status == JoinRequestStatus.pendingHost) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isUpdating ? null : onDecline,
                    child: Text(tr('Decline')),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: ValueKey('approve-request-${request.id}'),
                    onPressed: isUpdating ? null : onAccept,
                    child: Text(tr('Approve')),
                  ),
                ),
              ],
            ),
          ],
          if (request.status == JoinRequestStatus.pendingTraveler) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              tr('Approved by you. Waiting for the traveler to confirm.'),
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.green),
            ),
          ],
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final JoinRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      JoinRequestStatus.pendingHost => AppColors.terracotta,
      JoinRequestStatus.pendingTraveler ||
      JoinRequestStatus.confirmed => AppColors.green,
      JoinRequestStatus.declined ||
      JoinRequestStatus.withdrawn ||
      JoinRequestStatus.left => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status == JoinRequestStatus.pendingHost ? tr('New') : status.label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _EmptyRequests extends StatelessWidget {
  const _EmptyRequests();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_search_outlined,
              size: 44,
              color: AppColors.green,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              tr('No traveler requests yet'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tr(
                'New requests will appear here with the traveler’s profile and introduction.',
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
