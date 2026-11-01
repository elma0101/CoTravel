import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
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
        title: const Text('Cancel this trip?'),
        content: Text(
          trip.confirmedTravelerCount == 0
              ? 'The trip leaves Explore and pending requests are declined. This cannot be undone.'
              : 'Your ${trip.confirmedTravelerCount} confirmed ${trip.confirmedTravelerCount == 1 ? 'traveler' : 'travelers'} will be notified and pending requests declined. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep trip'),
          ),
          FilledButton(
            key: const ValueKey('confirm-cancel-trip'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel trip'),
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
    }, successMessage: 'Trip cancelled.');
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
        title: const Text('Leave this trip?'),
        content: Text(
          trip.isLateToLeave(DateTime.now())
              ? 'The free cancellation window ended on $deadline. You can still leave, but ${trip.hostName} will be told this was a late departure and remaining costs will rise for the group.'
              : 'You can leave freely until $deadline. Your seat is released and you leave the group chat.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            key: const ValueKey('confirm-leave-trip'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave trip'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await _runAction(
        context,
        () => controller.leaveTrip(request),
        successMessage: 'You left the trip.',
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
                            ? 'No requests need review'
                            : '$pending ${pending == 1 ? 'traveler' : 'travelers'} waiting',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Review profiles carefully. A seat is only locked after both sides confirm.',
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
                      pending == 0 ? 'View requests' : 'Review requests',
                    ),
                  ),
                ],
                if (!trip.hasStarted(DateTime.now())) ...[
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton(
                    key: const ValueKey('edit-trip'),
                    onPressed: () => context.push(AppRoutes.editTrip(trip.id)),
                    child: const Text('Edit trip'),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  key: const ValueKey('cancel-trip'),
                  onPressed: () => _confirmCancelTrip(context, ref),
                  child: const Text('Cancel trip'),
                ),
              ],
            ),
          );
        }

        final request = controller.requestForTrip(trip.id);
        if (request == null) {
          return _PanelShell(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Interested in this trip?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Introduce yourself to ${trip.hostName}. Your profile and note will be reviewed before anything is confirmed.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton(
                  key: const ValueKey('request-to-join'),
                  onPressed: trip.openSeats == 0
                      ? null
                      : () => _composeRequest(context, ref),
                  child: Text(
                    trip.openSeats == 0 ? 'Trip is full' : 'Request to join',
                  ),
                ),
              ],
            ),
          );
        }

        return _RequestStatusCard(
          trip: trip,
          request: request,
          isUpdating: controller.isUpdating(request.id),
          onLeave: () => _confirmLeave(context, controller, request),
          onWithdraw: () => _runAction(
            context,
            () => controller.withdraw(request),
            successMessage: 'Request withdrawn.',
          ),
          onConfirm: () => _runAction(
            context,
            () => controller.confirmAsTraveler(request, confirm: true),
            successMessage: 'Your place is confirmed.',
          ),
          onDecline: () => _runAction(
            context,
            () => controller.confirmAsTraveler(request, confirm: false),
            successMessage: 'The invitation was declined.',
          ),
        );
      },
    );
  }

  Future<void> _composeRequest(BuildContext context, WidgetRef ref) async {
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent to the host.')),
      );
    }
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
              controller.errorMessage ?? 'The request could not be updated.',
            ),
          ),
        );
      }
    }
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
                  'Request could not be sent.',
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
                'Introduce yourself',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Tell ${widget.trip.hostName} why this route and group feel like a good fit.',
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
                decoration: const InputDecoration(
                  hintText:
                      'Mention your travel pace, relevant experience, or what you hope to share with the group.',
                ),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length < 20 ? 'Write at least 20 characters' : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const ValueKey('send-join-request'),
                onPressed:
                    _isSending || _messageController.text.trim().length < 20
                    ? null
                    : _submit,
                child: Text(_isSending ? 'Sending…' : 'Send request'),
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
                  'This trip was cancelled',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'It is no longer open for requests. The group chat stays available for anyone already in it.',
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
        'Waiting for ${trip.hostName}',
        'Your request is sent. You can withdraw it while the host is reviewing your profile.',
      ),
      JoinRequestStatus.pendingTraveler => (
        Icons.handshake_outlined,
        AppColors.green,
        '${trip.hostName} approved your request',
        'Review the itinerary once more, then confirm to lock your place in the group.',
      ),
      JoinRequestStatus.confirmed => (
        Icons.check_circle_rounded,
        AppColors.green,
        'Your place is confirmed',
        trip.isLateToLeave(DateTime.now())
            ? 'Both you and the host agreed. The free cancellation window ended on ${formatTripDate(trip.freeCancellationUntil)}.'
            : 'Both you and the host agreed. You can leave freely until ${formatTripDate(trip.freeCancellationUntil)}.',
      ),
      JoinRequestStatus.declined => (
        Icons.cancel_outlined,
        AppColors.muted,
        'The host did not accept this request',
        'No place was reserved and the group size was not changed.',
      ),
      JoinRequestStatus.withdrawn => (
        Icons.undo_rounded,
        AppColors.muted,
        'Request withdrawn',
        'No place was reserved and the group size was not changed.',
      ),
      JoinRequestStatus.left => (
        Icons.logout_rounded,
        AppColors.muted,
        'You left this trip',
        'Your seat was released.',
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
              child: const Text('Withdraw request'),
            ),
          ],
          if (request.status == JoinRequestStatus.confirmed &&
              !trip.hasStarted(DateTime.now())) ...[
            const SizedBox(height: AppSpacing.md),
            TextButton(
              key: const ValueKey('leave-trip'),
              onPressed: isUpdating ? null : onLeave,
              child: const Text('Leave trip'),
            ),
          ],
          if (request.status == JoinRequestStatus.pendingTraveler) ...[
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
                    key: const ValueKey('confirm-trip-place'),
                    onPressed: isUpdating ? null : onConfirm,
                    child: const Text('Confirm place'),
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
