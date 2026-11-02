import '../../../core/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../safety/domain/safety_models.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../../safety/presentation/safety_actions.dart';
import '../domain/traveler_action_target.dart';
import '../domain/user_profile.dart';

class MemberProfileScreen extends ConsumerStatefulWidget {
  const MemberProfileScreen({
    required this.userId,
    this.tripId,
    this.conversationId,
    this.openedFromConversation = false,
    this.fallback,
    super.key,
  });

  final String userId;
  final String? tripId;
  final String? conversationId;
  final bool openedFromConversation;
  final TravelerActionTarget? fallback;

  @override
  ConsumerState<MemberProfileScreen> createState() =>
      _MemberProfileScreenState();
}

class _MemberProfileScreenState extends ConsumerState<MemberProfileScreen> {
  late Future<UserProfile?> _profile;

  @override
  void initState() {
    super.initState();
    _profile = ref.read(profileRepositoryProvider).fetchProfile(widget.userId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr('Traveler profile'))),
      body: FutureBuilder<UserProfile?>(
        future: _profile,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final profile = snapshot.data;
          if (profile == null) {
            return _UnavailableProfile(
              onRetry: () {
                setState(() {
                  _profile = ref
                      .read(profileRepositoryProvider)
                      .fetchProfile(widget.userId);
                });
              },
            );
          }
          return _MemberProfileBody(
            profile: profile,
            tripId: widget.tripId,
            tripTitle: widget.fallback?.tripTitle,
            preferredConversationId: widget.conversationId,
            openedFromConversation: widget.openedFromConversation,
          );
        },
      ),
    );
  }
}

class _MemberProfileBody extends ConsumerWidget {
  const _MemberProfileBody({
    required this.profile,
    required this.tripId,
    required this.tripTitle,
    required this.preferredConversationId,
    required this.openedFromConversation,
  });

  final UserProfile profile;
  final String? tripId;
  final String? tripTitle;
  final String? preferredConversationId;
  final bool openedFromConversation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    final safety = ref.watch(safetyControllerProvider);
    return ListenableBuilder(
      listenable: Listenable.merge([chat, safety]),
      builder: (context, child) {
        final conversation = preferredConversationId == null
            ? chat.conversationForTrip(tripId)
            : chat.conversationById(preferredConversationId!) ??
                  chat.conversationForTrip(tripId);
        final resolvedConversationId =
            conversation?.id ?? preferredConversationId;
        final isBlocked = safety.isBlocked(profile.id);
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.xxl,
                ),
                children: [
                  _ProfileHero(profile: profile),
                  const SizedBox(height: AppSpacing.xl),
                  if (profile.bio != null && profile.bio!.trim().isNotEmpty)
                    _ProfileSection(
                      title: tr('About'),
                      child: Text(
                        profile.bio!,
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(height: 1.5),
                      ),
                    ),
                  if (profile.travelStyles.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ProfileSection(
                      title: tr('Travel style'),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: profile.travelStyles
                            .map((style) => Chip(label: Text(tr(style))))
                            .toList(),
                      ),
                    ),
                  ],
                  if (profile.languages.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ProfileSection(
                      title: tr('Languages'),
                      child: Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: profile.languages
                            .map(
                              (language) => Chip(
                                avatar: const Icon(
                                  Icons.translate_rounded,
                                  size: 16,
                                ),
                                label: Text(language),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  _TrustFactsSection(profile: profile),
                  if (tripTitle != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    _ProfileSection(
                      title: tr('Shared trip'),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.route_rounded,
                            color: AppColors.green,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: Text(tripTitle!)),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  SafetyOptionsButton(
                    target: SafetyTarget(
                      userId: profile.id,
                      userName: profile.displayName ?? tr('CoTravel member'),
                      tripId: tripId,
                      tripTitle: tripTitle,
                    ),
                    onBlocked: () {
                      if (openedFromConversation && context.canPop()) {
                        context.pop();
                      } else {
                        context.go(AppRoutes.explore);
                      }
                    },
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: FilledButton.icon(
                  key: ValueKey('profile-message-${profile.id}'),
                  onPressed: resolvedConversationId == null || isBlocked
                      ? null
                      : () {
                          if (openedFromConversation && context.canPop()) {
                            context.pop();
                          } else {
                            context.push(
                              AppRoutes.conversation(resolvedConversationId),
                            );
                          }
                        },
                  icon: Icon(
                    isBlocked
                        ? Icons.block_rounded
                        : Icons.chat_bubble_outline_rounded,
                  ),
                  label: Text(
                    isBlocked
                        ? tr('Messaging unavailable while blocked')
                        : resolvedConversationId == null
                        ? tr('Messaging opens after trip confirmation')
                        : openedFromConversation
                        ? tr('Back to trip chat')
                        : tr('Message in trip chat'),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _TrustFactsSection extends ConsumerStatefulWidget {
  const _TrustFactsSection({required this.profile});

  final UserProfile profile;

  @override
  ConsumerState<_TrustFactsSection> createState() => _TrustFactsSectionState();
}

class _TrustFactsSectionState extends ConsumerState<_TrustFactsSection> {
  late final Future<TrustFacts?> _facts = ref
      .read(profileRepositoryProvider)
      .fetchTrustFacts(widget.profile.id);

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return FutureBuilder<TrustFacts?>(
      future: _facts,
      builder: (context, snapshot) {
        final facts = snapshot.data;
        final occupation = profile.occupation;
        final instagram = profile.instagramHandle;
        final lines = [
          if (facts != null) ...[
            tr('Member since {value}', {
              'value': formatMonthYear(facts.memberSince),
            }),
            trPlural(facts.tripsHosted, '{n} trip hosted', '{n} trips hosted'),
            trPlural(facts.tripsJoined, '{n} trip joined', '{n} trips joined'),
          ],
          if (occupation != null)
            tr('Occupation: {occupation} (self-declared)', {
              'occupation': occupation,
            }),
          if (instagram != null)
            tr('Instagram: @{instagram} (not verified)', {
              'instagram': instagram,
            }),
        ];
        if (lines.isEmpty) {
          return const SizedBox.shrink();
        }
        return _ProfileSection(
          title: tr('Track record'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                  child: Text(line),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: AppColors.greenSoft,
          foregroundImage: profile.avatarUrl == null
              ? null
              : NetworkImage(profile.avatarUrl!),
          child: profile.avatarUrl == null
              ? Text(
                  profile.initials,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w800,
                  ),
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          profile.displayName ?? tr('CoTravel member'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          profile.homeCity ?? tr('Home city not added'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: profile.isLinkedInVerified
                ? AppColors.greenSoft
                : AppColors.terracottaSoft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                profile.isLinkedInVerified
                    ? Icons.verified_rounded
                    : Icons.hourglass_top_rounded,
                size: 16,
                color: profile.isLinkedInVerified
                    ? AppColors.green
                    : AppColors.muted,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                profile.isLinkedInVerified
                    ? tr('Identity verified')
                    : tr('Verification pending'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProfileSection extends StatelessWidget {
  const _ProfileSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _UnavailableProfile extends StatelessWidget {
  const _UnavailableProfile({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.person_off_outlined,
              size: 44,
              color: AppColors.green,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              tr('Profile unavailable'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tr(
                'This profile may be incomplete, unavailable, or hidden by your safety settings.',
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            TextButton(onPressed: onRetry, child: Text(tr('Try again'))),
          ],
        ),
      ),
    );
  }
}
