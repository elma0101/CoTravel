import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/auth_errors.dart';

/// Why LinkedIn is being asked for, so the sheet can say what happens next.
enum LinkedInGateReason { join, host, profile }

/// True when the member may go on: they are verified, verification is not
/// required here, or they verify in the sheet this opens. The database makes
/// the same check when a trip is published or a request is sent.
Future<bool> ensureLinkedInVerified(
  BuildContext context,
  WidgetRef ref, {
  required LinkedInGateReason reason,
}) async {
  final required = ref.read(appConfigProvider).requireLinkedInVerification;
  final verified =
      ref.read(appAuthStateProvider).profile?.isLinkedInVerified == true;
  if (verified || (!required && reason != LinkedInGateReason.profile)) {
    return true;
  }
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _LinkedInGateSheet(reason: reason),
  );
  return result == true;
}

class _LinkedInGateSheet extends ConsumerStatefulWidget {
  const _LinkedInGateSheet({required this.reason});

  final LinkedInGateReason reason;

  @override
  ConsumerState<_LinkedInGateSheet> createState() => _LinkedInGateSheetState();
}

class _LinkedInGateSheetState extends ConsumerState<_LinkedInGateSheet> {
  late final AppLifecycleListener _lifecycle;
  bool _isOpening = false;
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    // Coming back from the browser: check again in case the change of
    // identity has not reached the app yet.
    _lifecycle = AppLifecycleListener(
      onResume: () =>
          unawaited(ref.read(appAuthStateProvider).refreshProfile()),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    setState(() => _isOpening = true);
    try {
      final launched = await ref.read(appAuthStateProvider).linkLinkedIn();
      if (!launched && mounted) {
        _showMessage(tr('LinkedIn could not be opened. Please try again.'));
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
          readableAuthError(error) ??
              tr('LinkedIn could not be opened. Please try again.'),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isOpening = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(appAuthStateProvider);
    return ListenableBuilder(
      listenable: authState,
      builder: (context, child) {
        final verified = authState.profile?.isLinkedInVerified == true;
        if (verified && !_closed) {
          _closed = true;
          unawaited(HapticFeedback.mediumImpact());
          // Give the check mark a moment, then carry on with what was asked.
          Future<void>.delayed(const Duration(milliseconds: 700), () {
            if (mounted) {
              Navigator.of(this.context).pop(true);
            }
          });
        }
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Icon(
                    verified ? Icons.verified_rounded : Icons.badge_outlined,
                    key: ValueKey(verified),
                    size: 56,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  verified ? tr('You are verified!') : _title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  verified
                      ? _afterVerification
                      : tr(
                          'Every host and traveler on CoTravel is verified with LinkedIn, so groups know who they travel with. CoTravel never posts to LinkedIn.',
                        ),
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                const SizedBox(height: AppSpacing.lg),
                if (!verified) ...[
                  FilledButton.icon(
                    key: const ValueKey('linkedin-gate-verify'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                    ),
                    onPressed: _isOpening ? null : _verify,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: Text(
                      _isOpening ? tr('Opening…') : tr('Verify with LinkedIn'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(tr('Not now')),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String get _title => switch (widget.reason) {
    LinkedInGateReason.join => tr('One quick step before you join'),
    LinkedInGateReason.host => tr('One quick step before you host'),
    LinkedInGateReason.profile => tr('Verify your profile'),
  };

  String get _afterVerification => switch (widget.reason) {
    LinkedInGateReason.join => tr('Now let’s send your request.'),
    LinkedInGateReason.host => tr('Now let’s plan your trip.'),
    LinkedInGateReason.profile => tr(
      'Your profile now shows the verified badge.',
    ),
  };
}
