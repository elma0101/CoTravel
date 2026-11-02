import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

class CheckEmailScreen extends StatelessWidget {
  const CheckEmailScreen({required this.email, super.key});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton(
                onPressed: () => context.go('/welcome'),
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: tr('Back'),
              ),
              const Spacer(),
              Container(
                width: 76,
                height: 76,
                decoration: const BoxDecoration(
                  color: AppColors.terracottaSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.mark_email_read_outlined,
                  color: AppColors.terracotta,
                  size: 36,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                tr('Check your email'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                email.isEmpty
                    ? tr('Use the secure link we sent to finish signing in.')
                    : tr('We sent a secure sign-in link to {email}.', {
                        'email': email,
                      }),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                tr(
                  'You can close this screen after opening the link. CoTravel will return here automatically.',
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => context.go('/welcome'),
                child: Text(tr('Use another email')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
