import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/beta_feedback_controller.dart';
import '../domain/beta_feedback.dart';

class BetaFeedbackScreen extends ConsumerStatefulWidget {
  const BetaFeedbackScreen({super.key});

  @override
  ConsumerState<BetaFeedbackScreen> createState() => _BetaFeedbackScreenState();
}

class _BetaFeedbackScreenState extends ConsumerState<BetaFeedbackScreen> {
  final _commentsController = TextEditingController();
  BetaExperienceArea _area = BetaExperienceArea.discovery;
  int? _score;
  bool _submitted = false;

  @override
  void dispose() {
    _commentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(betaFeedbackControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Beta feedback')),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, child) {
          if (_submitted) {
            return _ThankYou(
              onAnotherResponse: () {
                setState(() {
                  _submitted = false;
                  _score = null;
                  _commentsController.clear();
                });
              },
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              const _BetaIntroduction(),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'What were you doing?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              DropdownButtonFormField<BetaExperienceArea>(
                key: const ValueKey('beta-experience-area'),
                initialValue: _area,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.route_outlined),
                ),
                items: BetaExperienceArea.values
                    .map(
                      (area) => DropdownMenuItem(
                        value: area,
                        child: Text(area.label),
                      ),
                    )
                    .toList(),
                onChanged: controller.isSubmitting
                    ? null
                    : (value) {
                        if (value != null) {
                          setState(() => _area = value);
                        }
                      },
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                'Did CoTravel help you feel safe and informed?',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Choose one response. This is the main measure for our beta.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              _ScorePicker(
                value: _score,
                enabled: !controller.isSubmitting,
                onChanged: (value) => setState(() => _score = value),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('Not at all'), Text('Very much')],
              ),
              const SizedBox(height: AppSpacing.xl),
              TextField(
                key: const ValueKey('beta-comments'),
                controller: _commentsController,
                enabled: !controller.isSubmitting,
                maxLength: 1000,
                minLines: 4,
                maxLines: 7,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'What should we improve? (optional)',
                  alignLabelWithHint: true,
                  hintText: 'Tell us what felt clear, confusing, or missing.',
                ),
              ),
              if (controller.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  controller.errorMessage!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.error),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                key: const ValueKey('submit-beta-feedback'),
                onPressed: _score == null || controller.isSubmitting
                    ? null
                    : () => _submit(controller),
                child: controller.isSubmitting
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send feedback'),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Your response is linked to your beta account so repeated responses do not multiply your weight. It is visible only to the beta team.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _submit(BetaFeedbackController controller) async {
    FocusScope.of(context).unfocus();
    try {
      await controller.submit(
        BetaFeedbackDraft(
          experienceArea: _area,
          safeInformedScore: _score!,
          comments: _commentsController.text,
        ),
      );
      if (mounted) {
        setState(() => _submitted = true);
      }
    } on Object {
      // The controller exposes a readable error beside the form.
    }
  }
}

class _BetaIntroduction extends StatelessWidget {
  const _BetaIntroduction();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.forum_outlined, color: AppColors.green, size: 30),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Help shape a calmer way to travel together.',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A focused response after a real task is more useful than a long survey. This takes about a minute.',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _ScorePicker extends StatelessWidget {
  const _ScorePicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int? value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var score = 1; score <= 5; score++) ...[
          if (score > 1) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Semantics(
              label: '$score out of 5',
              selected: value == score,
              button: true,
              child: InkWell(
                key: ValueKey('beta-score-$score'),
                onTap: enabled ? () => onChanged(score) : null,
                borderRadius: BorderRadius.circular(14),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == score ? AppColors.green : AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: value == score
                          ? AppColors.green
                          : AppColors.border,
                    ),
                  ),
                  child: Text(
                    '$score',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: value == score ? Colors.white : AppColors.ink,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThankYou extends StatelessWidget {
  const _ThankYou({required this.onAnotherResponse});

  final VoidCallback onAnotherResponse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 460),
          padding: const EdgeInsets.all(AppSpacing.xl),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              const CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.greenSoft,
                foregroundColor: AppColors.green,
                child: Icon(Icons.check_rounded, size: 36),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Thank you',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Your response is part of the controlled-beta readout.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                key: const ValueKey('another-beta-response'),
                onPressed: onAnotherResponse,
                child: const Text('Share another experience'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
