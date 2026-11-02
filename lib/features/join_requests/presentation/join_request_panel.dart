import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../profile/presentation/linkedin_gate.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../trips/domain/trip.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../application/join_request_controller.dart';
import '../domain/trip_join_request.dart';

class JoinRequestPanel extends ConsumerWidget {
  const JoinRequestPanel({required this.trip, super.key});

  final Trip trip;

  Future<void> _confirmCancelTrip(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Cancel this trip?')),
        content: Text(
          trip.confirmedTravelerCount == 0
              ? tr(
                  'The trip leaves Explore and pending requests are declined. This cannot be undone.',
                )
              : trPlural(
                  trip.confirmedTravelerCount,
                  'Your {n} confirmed traveler will be notified and pending requests declined. This cannot be undone.',
                  'Your {n} confirmed travelers will be notified and pending requests declined. This cannot be undone.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Keep trip')),
          ),
          FilledButton(
            key: const ValueKey('confirm-cancel-trip'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Cancel trip')),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) {
      return;
    }
    await _runAction(context, () async {
      await ref.read(tripCatalogProvider).cancelTrip(trip);
      await ref.read(joinRequestControllerProvider).load();
    }, successMessage: tr('Trip cancelled.'));
  }

  Future<void> _confirmLeave(
    BuildContext context,
    JoinRequestController controller,
    TripJoinRequest request,
  ) async {
    final deadline = formatTripDate(trip.freeCancellationUntil);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Leave this trip?')),
        content: Text(
          trip.isLateToLeave(DateTime.now())
              ? tr(
                  'The free cancellation window ended on {deadline}. You can still leave, but {hostName} will be told this was a late departure and remaining costs will rise for the group.',
                  {'hostName': trip.hostName, 'deadline': deadline},
                )
              : tr(
                  'You can leave freely until {deadline}. Your seat is released and you leave the group chat.',
                  {'deadline': deadline},
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Stay')),
          ),
          FilledButton(
            key: const ValueKey('confirm-leave-trip'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Leave trip')),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAction(
        context,
        () => controller.leaveTrip(request),
        successMessage: tr('You left the trip.'),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(joinRequestControllerProvider);
    final userId = ref.watch(appAuthStateProvider).profile?.id;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        if (controller.isLoading) {
          return const _PanelShell(
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (trip.isCancelled) {
          return const _CancelledTripNotice();
        }
        if (trip.hostId == userId) {
          final requests = controller.hostRequestsForTrip(trip.id);
          final pending = requests
              .where(
                (request) => request.status == JoinRequestStatus.pendingHost,
              )
              .length;
          return _PanelShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.how_to_reg_outlined,
                      color: AppColors.green,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        pending == 0
                            ? tr('No requests need review')
                            : trPlural(
                                pending,
                                '{n} traveler waiting',
                                '{n} travelers waiting',
                              ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tr(
                    'Review profiles carefully. A seat is only locked after both sides confirm.',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                if (requests.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(
                    onPressed: () =>
                        context.push(AppRoutes.tripRequests(trip.id)),
                    child: Text(
                      pending == 0
                          ? tr('View requests')
                          : tr('Review requests'),
                    ),
                  ),
                ],
                if (!trip.hasStarted(DateTime.now())) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    key: const ValueKey('edit-trip'),
                    onPressed: () => context.push(AppRoutes.editTrip(trip.id)),
                    child: Text(tr('Edit trip')),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  key: const ValueKey('cancel-trip'),
                  onPressed: () => _confirmCancelTrip(context, ref),
                  child: Text(tr('Cancel trip')),
                ),
              ],
            ),
          );
        }

        final request = controller.requestForTrip(trip.id);
        // A visitor's only action lives in JoinRequestBar.
        if (request == null) {
          return const SizedBox.shrink();
        }

        return _RequestStatusCard(
          trip: trip,
          request: request,
          isUpdating: controller.isUpdating(request.id),
          onLeave: () => _confirmLeave(context, controller, request),
          onWithdraw: () => _runAction(
            context,
            () => controller.withdraw(request),
            successMessage: tr('Request withdrawn.'),
          ),
          onConfirm: () => _runAction(
            context,
            () => controller.confirmAsTraveler(request, confirm: true),
            successMessage: tr('Your place is confirmed.'),
          ),
          onDecline: () => _runAction(
            context,
            () => controller.confirmAsTraveler(request, confirm: false),
            successMessage: tr('The invitation was declined.'),
          ),
        );
      },
    );
  }

  Future<void> _runAction(
    BuildContext context,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    try {
      await action();
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on Object {
      if (context.mounted) {
        final controller = ProviderScope.containerOf(
          context,
        ).read(joinRequestControllerProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              controller.errorMessage ??
                  tr('The request could not be updated.'),
            ),
          ),
        );
      }
    }
  }
}

/// The mockup's fixed footer: group size for everyone, and the join action for
/// a visitor who has not asked yet.
class JoinRequestBar extends ConsumerWidget {
  const JoinRequestBar({required this.trip, super.key});

  final Trip trip;

  Future<void> _composeRequest(BuildContext context, WidgetRef ref) async {
    final verified = await ensureLinkedInVerified(
      context,
      ref,
      reason: LinkedInGateReason.join,
    );
    if (!verified || !context.mounted) {
      return;
    }
    final requestController = ref.read(joinRequestControllerProvider);

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _JoinRequestComposer(
        trip: trip,
        requestController: requestController,
      ),
    );

    if (submitted == true && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(tr('Request sent to the host.'))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(joinRequestControllerProvider);
    final userId = ref.watch(appAuthStateProvider).profile?.id;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final canRequest =
            !controller.isLoading &&
            !trip.isCancelled &&
            trip.hostId != userId &&
            controller.requestForTrip(trip.id) == null;
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.sm,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        tr('Group'),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          tr('{participantCount} of {capacity} confirmed', {
                            'participantCount': trip.participantCount,
                            'capacity': trip.capacity,
                          }),
                          key: const ValueKey('trip-group-count'),
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (canRequest) ...[
                    const SizedBox(height: AppSpacing.sm),
                    ElevatedButton(
                      key: const ValueKey('request-to-join'),
                      onPressed: trip.openSeats == 0
                          ? null
                          : () => _composeRequest(context, ref),
                      child: Text(
                        trip.openSeats == 0
                            ? tr('Trip is full')
                            : tr('Request to join'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _JoinRequestComposer extends StatefulWidget {
  const _JoinRequestComposer({
    required this.trip,
    required this.requestController,
  });

  final Trip trip;
  final JoinRequestController requestController;

  @override
  State<_JoinRequestComposer> createState() => _JoinRequestComposerState();
}

class _JoinRequestComposerState extends State<_JoinRequestComposer> {
  final _messageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSending = false;
  bool _availableAllDates = false;
  bool _budgetFits = false;
  bool _canShareDriving = false;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await widget.requestController.submitRequest(
        trip: widget.trip,
        message: _messageController.text,
        availableAllDates: _availableAllDates,
        budgetFits: _budgetFits,
        canShareDriving: _canShareDriving,
      );
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.requestController.errorMessage ??
                  tr('Request could not be sent.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                tr('Introduce yourself'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tr(
                  'Tell {hostName} why this route and group feel like a good fit.',
                  {'hostName': widget.trip.hostName},
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                key: const ValueKey('join-request-message'),
                controller: _messageController,
                autofocus: true,
                minLines: 4,
                maxLines: 6,
                maxLength: 300,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: tr(
                    'Mention your travel pace, relevant experience, or what you hope to share with the group.',
                  ),
                ),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length < 20
                      ? tr('Write at least 20 characters')
                      : null;
                },
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('join-available-all-dates'),
                contentPadding: EdgeInsets.zero,
                value: _availableAllDates,
                onChanged: (value) =>
                    setState(() => _availableAllDates = value),
                title: Text(tr('I am free for all the dates')),
                subtitle: Text(
                  formatTripDateRange(
                    widget.trip.startDate,
                    widget.trip.endDate,
                  ),
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('join-budget-fits'),
                contentPadding: EdgeInsets.zero,
                value: _budgetFits,
                onChanged: (value) => setState(() => _budgetFits = value),
                title: Text(tr('This budget works for me')),
                subtitle: Text(
                  tr('About {amount} each with a full group', {
                    'amount': formatTripMoney(
                      widget.trip.estimatedFullGroupShare,
                      widget.trip.currency,
                    ),
                  }),
                ),
              ),
              SwitchListTile.adaptive(
                key: const ValueKey('join-can-drive'),
                contentPadding: EdgeInsets.zero,
                value: _canShareDriving,
                onChanged: (value) => setState(() => _canShareDriving = value),
                title: Text(tr('I can share driving')),
                subtitle: Text(tr('CoTravel does not check driving licences.')),
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const ValueKey('send-join-request'),
                onPressed:
                    _isSending || _messageController.text.trim().length < 20
                    ? null
                    : _submit,
                child: Text(_isSending ? tr('Sending…') : tr('Send request')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelShell extends StatelessWidget {
  const _PanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: child,
    );
  }
}

class _CancelledTripNotice extends StatelessWidget {
  const _CancelledTripNotice();

  @override
  Widget build(BuildContext context) {
    return _PanelShell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.event_busy_outlined, color: AppColors.terracotta),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('This trip was cancelled'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  tr(
                    'It is no longer open for requests. The group chat stays available for anyone already in it.',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestStatusCard extends StatelessWidget {
  const _RequestStatusCard({
    required this.trip,
    required this.request,
    required this.isUpdating,
    required this.onWithdraw,
    required this.onLeave,
    required this.onConfirm,
    required this.onDecline,
  });

  final Trip trip;
  final TripJoinRequest request;
  final bool isUpdating;
  final VoidCallback onWithdraw;
  final VoidCallback onLeave;
  final VoidCallback onConfirm;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title, message) = switch (request.status) {
      JoinRequestStatus.pendingHost => (
        Icons.schedule_rounded,
        AppColors.terracotta,
        tr('Waiting for {hostName}', {'hostName': trip.hostName}),
        tr(
          'Your request is sent. You can withdraw it while the host is reviewing your profile.',
        ),
      ),
      JoinRequestStatus.pendingTraveler => (
        Icons.handshake_outlined,
        AppColors.green,
        tr('{hostName} approved your request', {'hostName': trip.hostName}),
        tr(
          'Review the itinerary once more, then confirm to lock your place in the group.',
        ),
      ),
      JoinRequestStatus.confirmed => (
        Icons.check_circle_rounded,
        AppColors.green,
        tr('Your place is confirmed'),
        trip.isLateToLeave(DateTime.now())
            ? tr(
                'Both you and the host agreed. The free cancellation window ended on {date}.',
                {'date': formatTripDate(trip.freeCancellationUntil)},
              )
            : tr(
                'Both you and the host agreed. You can leave freely until {date}.',
                {'date': formatTripDate(trip.freeCancellationUntil)},
              ),
      ),
      JoinRequestStatus.declined => (
        Icons.cancel_outlined,
        AppColors.muted,
        tr('The host did not accept this request'),
        tr('No place was reserved and the group size was not changed.'),
      ),
      JoinRequestStatus.withdrawn => (
        Icons.undo_rounded,
        AppColors.muted,
        tr('Request withdrawn'),
        tr('No place was reserved and the group size was not changed.'),
      ),
      JoinRequestStatus.left => (
        Icons.logout_rounded,
        AppColors.muted,
        tr('You left this trip'),
        tr('Your seat was released.'),
      ),
    };

    return _PanelShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      message,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (request.status == JoinRequestStatus.pendingHost) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              onPressed: isUpdating ? null : onWithdraw,
              child: Text(tr('Withdraw request')),
            ),
          ],
          if (request.status == JoinRequestStatus.confirmed &&
              !trip.hasStarted(DateTime.now())) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              key: const ValueKey('leave-trip'),
              onPressed: isUpdating ? null : onLeave,
              child: Text(tr('Leave trip')),
            ),
          ],
          if (request.status == JoinRequestStatus.pendingTraveler) ...[
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
                    key: const ValueKey('confirm-trip-place'),
                    onPressed: isUpdating ? null : onConfirm,
                    child: Text(tr('Confirm place')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
