import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/safety_models.dart';

class SafetyOptionsButton extends ConsumerWidget {
  const SafetyOptionsButton({required this.target, this.onBlocked, super.key});

  final SafetyTarget target;
  final VoidCallback? onBlocked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentUserId = ref.watch(appAuthStateProvider).profile?.id;
    if (currentUserId == target.userId) {
      return const SizedBox.shrink();
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: TextButton.icon(
        key: ValueKey('safety-options-${target.userId}'),
        onPressed: () => _open(context, ref),
        icon: const Icon(Icons.shield_outlined),
        label: const Text('Report or block'),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_SafetyActionResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _SafetyActionSheet(target: target),
    );
    if (result == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(result.message)));
    if (result.blocked) {
      onBlocked?.call();
    }
  }
}

class _SafetyActionSheet extends ConsumerStatefulWidget {
  const _SafetyActionSheet({required this.target});

  final SafetyTarget target;

  @override
  ConsumerState<_SafetyActionSheet> createState() => _SafetyActionSheetState();
}

class _SafetyActionSheetState extends ConsumerState<_SafetyActionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _detailsController = TextEditingController();
  SafetyReportReason _reason = SafetyReportReason.harassment;
  bool _alsoBlock = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(safetyControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final blocked = controller.isBlocked(widget.target.userId);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Safety options',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      widget.target.userName,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: AppColors.greenSoft,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'If anyone is in immediate danger, contact local emergency services. CoTravel reports are reviewed manually and are not an emergency channel.',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    if (!blocked)
                      OutlinedButton.icon(
                        key: const ValueKey('block-user'),
                        onPressed: controller.isSubmitting ? null : _block,
                        icon: const Icon(Icons.block_rounded),
                        label: Text('Block ${widget.target.userName}'),
                      )
                    else
                      const Row(
                        children: [
                          Icon(Icons.block_rounded, color: AppColors.muted),
                          SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'This person is already blocked. You can unblock them from the Safety Center.',
                            ),
                          ),
                        ],
                      ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
                      child: Divider(),
                    ),
                    Text(
                      'Send a report',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    DropdownButtonFormField<SafetyReportReason>(
                      key: const ValueKey('safety-report-reason'),
                      initialValue: _reason,
                      decoration: const InputDecoration(labelText: 'Reason'),
                      items: SafetyReportReason.values
                          .map(
                            (reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(reason.label),
                            ),
                          )
                          .toList(),
                      onChanged: (reason) {
                        if (reason != null) {
                          setState(() => _reason = reason);
                        }
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      key: const ValueKey('safety-report-details'),
                      controller: _detailsController,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: const InputDecoration(
                        labelText: 'What happened?',
                        hintText:
                            'Share the specific behavior or trip detail the moderator should review.',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) {
                        final length = value?.trim().length ?? 0;
                        return length < 10
                            ? 'Add at least 10 characters'
                            : null;
                      },
                    ),
                    if (!blocked)
                      CheckboxListTile(
                        value: _alsoBlock,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('Also block this person'),
                        subtitle: const Text(
                          'Their trips disappear from discovery immediately.',
                        ),
                        onChanged: controller.isSubmitting
                            ? null
                            : (value) {
                                setState(() => _alsoBlock = value ?? false);
                              },
                      ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        controller.errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      key: const ValueKey('submit-safety-report'),
                      onPressed: controller.isSubmitting ? null : _submit,
                      child: Text(
                        controller.isSubmitting
                            ? 'Submitting…'
                            : 'Submit report',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _block() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block ${widget.target.userName}?'),
        content: const Text(
          'Their trips will be hidden and neither of you can create new join requests with the other.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-block-user'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(safetyControllerProvider).block(widget.target);
      if (mounted) {
        Navigator.of(context).pop(
          _SafetyActionResult(
            message: '${widget.target.userName} was blocked.',
            blocked: true,
          ),
        );
      }
    } on Object {
      // The controller renders the readable failure inside the sheet.
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    try {
      await ref
          .read(safetyControllerProvider)
          .submitReport(
            target: widget.target,
            reason: _reason,
            details: _detailsController.text,
          );
      var blocked = false;
      if (_alsoBlock) {
        await ref.read(safetyControllerProvider).block(widget.target);
        blocked = true;
      }
      if (mounted) {
        Navigator.of(context).pop(
          _SafetyActionResult(
            message: 'Report submitted for manual review.',
            blocked: blocked,
          ),
        );
      }
    } on Object {
      // The controller renders the readable failure inside the sheet.
    }
  }
}

class _SafetyActionResult {
  const _SafetyActionResult({required this.message, required this.blocked});

  final String message;
  final bool blocked;
}
