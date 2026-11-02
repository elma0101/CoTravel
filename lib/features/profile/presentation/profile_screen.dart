import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/auth/app_auth_state.dart';
import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/screen_header.dart';
import '../domain/user_profile.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(appAuthStateProvider);

    return ListenableBuilder(
      listenable: authState,
      builder: (context, child) {
        final profile = authState.profile;
        return SafeArea(
          child: ListView(
            children: [
              ScreenHeader(
                title: tr('Profile'),
                subtitle: tr('Build trust before the journey begins.'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _ProfileSummary(profile: profile),
              ),
              const SizedBox(height: AppSpacing.lg),
              _VerificationTile(
                isVerified: profile?.isLinkedInVerified == true,
              ),
              _ProfileTile(
                key: const ValueKey('open-edit-profile'),
                icon: Icons.tune_rounded,
                title: tr('Edit profile and preferences'),
                onTap: () => context.push(AppRoutes.editProfile),
              ),
              _ProfileTile(
                key: const ValueKey('open-safety-center'),
                icon: Icons.help_outline_rounded,
                title: tr('Help & safety'),
                onTap: () => context.push(AppRoutes.safety),
              ),
              _ProfileTile(
                key: const ValueKey('open-beta-feedback'),
                icon: Icons.forum_outlined,
                title: tr('Beta feedback'),
                onTap: () => context.push(AppRoutes.betaFeedback),
              ),
              _ProfileTile(
                key: const ValueKey('open-terms'),
                icon: Icons.description_outlined,
                title: tr('Terms of use'),
                onTap: () => context.push(AppRoutes.terms),
              ),
              _ProfileTile(
                key: const ValueKey('open-privacy'),
                icon: Icons.privacy_tip_outlined,
                title: tr('Privacy policy'),
                onTap: () => context.push(AppRoutes.privacy),
              ),
              _ProfileTile(
                icon: Icons.logout_rounded,
                title: tr('Sign out'),
                onTap: authState.signOut,
              ),
              _ProfileTile(
                key: const ValueKey('delete-account'),
                icon: Icons.delete_outline_rounded,
                title: tr('Delete account'),
                onTap: () => _confirmDeleteAccount(context, authState),
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _confirmDeleteAccount(
  BuildContext context,
  AppAuthState authState,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(tr('Delete your account?')),
        content: Text(
          tr(
            'This removes your profile, photo, requests, and the trips you created, and it cannot be undone. Messages you sent stay visible to their group as "Former member", and safety reports are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Keep account')),
          ),
          TextButton(
            key: const ValueKey('confirm-delete-account'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete account')),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) {
    return;
  }

  final messenger = ScaffoldMessenger.of(context);
  try {
    await authState.deleteAccount();
  } on PostgrestException catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  } on Object {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          tr('Your account could not be deleted. Please try again.'),
        ),
      ),
    );
  }
}

class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final UserProfile? profile;

  @override
  Widget build(BuildContext context) {
    final imageUrl = profile?.avatarUrl;
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
                radius: 30,
                backgroundColor: AppColors.greenSoft,
                foregroundImage: imageUrl == null
                    ? null
                    : NetworkImage(imageUrl),
                child: imageUrl == null
                    ? Text(
                        profile?.initials ?? '?',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.green,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.displayName ?? tr('Your travel profile'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      profile?.homeCity ?? tr('Add your home city'),
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
          if (profile?.bio != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(profile!.bio!, style: Theme.of(context).textTheme.bodyMedium),
          ],
          if (profile?.travelStyles.isNotEmpty == true) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: profile!.travelStyles
                  .map(
                    (style) => Chip(
                      label: Text(tr(style)),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _VerificationTile extends StatelessWidget {
  const _VerificationTile({required this.isVerified});

  final bool isVerified;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(
        isVerified ? Icons.verified_rounded : Icons.verified_user_outlined,
        color: isVerified ? AppColors.green : AppColors.terracotta,
      ),
      title: Text(
        isVerified ? tr('LinkedIn verified') : tr('Verification pending'),
      ),
      subtitle: Text(
        isVerified
            ? tr('Your professional identity is connected.')
            : tr('Connect a professional identity to strengthen trust.'),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => context.push(AppRoutes.editProfile),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.icon,
    required this.title,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      leading: Icon(icon, color: AppColors.green),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}
