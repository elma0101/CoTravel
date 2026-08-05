import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../application/join_request_controller.dart';
import '../domain/trip_join_request.dart';

class TripRequestsScreen extends ConsumerWidget {
  const TripRequestsScreen({required this.tripId, super.key});

  final String tripId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(joinRequestControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Traveler requests')),
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
        title: const Text('Decline this request?'),
        content: Text(
          '${request.travelerName} will see that the request was not accepted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep reviewing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Decline'),
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
                  ? 'Approved. ${request.travelerName} must now confirm.'
                  : 'Request declined.',
            ),
          ),
        );
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.errorMessage ?? 'Request could not be updated.',
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
          'Review the traveler’s profile and note. Approval invites them to confirm; it does not lock a seat yet.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _CandidateCard extends StatelessWidget {
  const _CandidateCard({
    required this.request,
    required this.isUpdating,
    required this.onAccept,
    required this.onDecline,
  });

  final TripJoinRequest request;
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
                      request.travelerHomeCity ?? 'CoTravel traveler',
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
          if (request.status == JoinRequestStatus.pendingHost) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isUpdating ? null : onDecline,
                    child: const Text('Decline'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    key: ValueKey('approve-request-${request.id}'),
                    onPressed: isUpdating ? null : onAccept,
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
          if (request.status == JoinRequestStatus.pendingTraveler) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              'Approved by you. Waiting for the traveler to confirm.',
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
      JoinRequestStatus.withdrawn => AppColors.muted,
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
        status == JoinRequestStatus.pendingHost ? 'New' : status.label,
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
              'No traveler requests yet',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'New requests will appear here with the traveler’s profile and introduction.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
