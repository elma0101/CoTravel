import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/l10n/server_errors.dart';
import '../../../core/widgets/step_flow.dart';
import '../../trips/presentation/widgets/place_field.dart';
import '../domain/user_profile.dart';

/// Sign-up as a few quick screens, one question each. Only the name is typed;
/// a bio, occupation and Instagram can be added later from the profile, and
/// LinkedIn is asked for the first time someone joins or hosts a trip.
class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  static const travelStyles = [
    ('Culture', Icons.account_balance_outlined),
    ('Food', Icons.restaurant_outlined),
    ('Nature', Icons.forest_outlined),
    ('Road trips', Icons.directions_car_outlined),
    ('Budget', Icons.savings_outlined),
    ('Remote work', Icons.laptop_mac_outlined),
  ];

  static const homeCities = [
    'Casablanca',
    'Rabat',
    'Marrakech',
    'Tangier',
    'Fes',
    'Agadir',
  ];

  static const languages = [
    'Arabic',
    'French',
    'English',
    'Tamazight',
    'Spanish',
    'German',
    'Italian',
  ];

  @override
  ConsumerState<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  static const _stepCount = 5;
  static const _maxStyles = 5;
  static const _maxLanguages = 8;

  final _pageController = PageController();
  final _nameController = TextEditingController();
  final _otherCityController = TextEditingController();
  final _otherLanguageController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _styles = <String>{};
  final _languages = <String>{};
  final _extraLanguages = <String>[];

  int _step = 0;
  String? _homeCity;
  bool _choosingOtherCity = false;
  Uint8List? _avatarBytes;
  String _avatarExtension = 'jpg';
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appAuthStateProvider).profile;
    if (profile != null) {
      _nameController.text = profile.displayName ?? '';
      _homeCity = profile.homeCity;
      _styles.addAll(profile.travelStyles);
      _languages.addAll(profile.languages);
      _extraLanguages.addAll(
        profile.languages.where(
          (language) => !ProfileSetupScreen.languages.contains(language),
        ),
      );
    }
    _nameController.addListener(_refresh);
    unawaited(_restoreLostImage());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _otherCityController.dispose();
    _otherLanguageController.dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  String get _name => _nameController.text.trim();

  bool get _canContinue => switch (_step) {
    0 => _name.length >= 2 && _name.length <= 60,
    2 => _styles.isNotEmpty,
    3 => _languages.isNotEmpty,
    _ => true,
  };

  Future<void> _goTo(int step) async {
    FocusScope.of(context).unfocus();
    setState(() => _step = step);
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _next() async {
    if (!_canContinue) {
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    if (_step == 1 && _choosingOtherCity) {
      final typed = _otherCityController.text.trim();
      _homeCity = typed.isEmpty ? _homeCity : typed;
    }
    await _goTo(_step + 1);
  }

  void _back() {
    if (_step > 0) {
      unawaited(_goTo(_step - 1));
    }
  }

  Future<void> _pickAvatar() async {
    final image = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    if (image != null) {
      await _useImage(image);
    }
  }

  Future<void> _restoreLostImage() async {
    final response = await _imagePicker.retrieveLostData();
    final files = response.files;
    if (files != null && files.isNotEmpty) {
      await _useImage(files.first);
    }
  }

  Future<void> _useImage(XFile image) async {
    final bytes = await image.readAsBytes();
    if (!mounted) {
      return;
    }
    setState(() {
      _avatarBytes = bytes;
      _avatarExtension = image.name.split('.').last.toLowerCase();
    });
  }

  void _toggle(Set<String> selection, String value, int limit) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (!selection.remove(value) && selection.length < limit) {
        selection.add(value);
      }
    });
  }

  void _addOtherLanguage() {
    final language = _otherLanguageController.text.trim();
    if (language.length < 2 || _languages.length >= _maxLanguages) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      if (!_extraLanguages.contains(language) &&
          !ProfileSetupScreen.languages.contains(language)) {
        _extraLanguages.add(language);
      }
      _languages.add(language);
      _otherLanguageController.clear();
    });
  }

  Future<void> _finish() async {
    setState(() => _isSaving = true);
    try {
      await ref
          .read(appAuthStateProvider)
          .completeProfile(
            draft: ProfileDraft(
              displayName: _name,
              bio: '',
              homeCity: _homeCity ?? '',
              travelStyles: _styles.toList(),
              languages: _languages.toList(),
              instagramHandle: '',
              occupation: '',
            ),
            avatarBytes: _avatarBytes,
            avatarExtension: _avatarExtension,
          );
      unawaited(HapticFeedback.mediumImpact());
    } on Object catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              readableServerError(error) ??
                  tr('Something went wrong. Please try again.'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(appAuthStateProvider);
    final isLastStep = _step == _stepCount - 1;

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _back();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _step == 0
              ? null
              : IconButton(
                  tooltip: tr('Back'),
                  onPressed: _back,
                  icon: const Icon(Icons.arrow_back_rounded),
                ),
          automaticallyImplyLeading: false,
          title: FlowProgressBar(step: _step, count: _stepCount),
          actions: [
            if (_step == 0)
              TextButton(
                onPressed: authState.signOut,
                child: Text(tr('Sign out')),
              ),
          ],
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _nameStep(),
                    _cityStep(),
                    _stylesStep(),
                    _languagesStep(),
                    _readyStep(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton(
                      key: ValueKey(
                        isLastStep ? 'finish-setup' : 'setup-continue',
                      ),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: isLastStep
                          ? (_isSaving ? null : _finish)
                          : (_canContinue ? _next : null),
                      child: Text(
                        isLastStep
                            ? (_isSaving
                                  ? tr('Saving profile…')
                                  : tr('Agree and start exploring'))
                            : tr('Continue'),
                      ),
                    ),
                    if (_step == 1)
                      TextButton(
                        key: const ValueKey('setup-skip'),
                        onPressed: () {
                          _homeCity = null;
                          unawaited(_goTo(_step + 1));
                        },
                        child: Text(tr('Skip for now')),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _nameStep() {
    final profile = ref.read(appAuthStateProvider).profile;
    return FlowStep(
      title: tr('Hi! What should we call you?'),
      subtitle: tr('This is how travelers will see you.'),
      children: [
        Center(
          child: _AvatarPicker(
            avatarBytes: _avatarBytes,
            avatarUrl: profile?.avatarUrl,
            initials: _name.isEmpty ? '?' : _name[0].toUpperCase(),
            onTap: _pickAvatar,
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const ValueKey('setup-name'),
          controller: _nameController,
          autofocus: _nameController.text.isEmpty,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          maxLength: 60,
          style: Theme.of(context).textTheme.titleLarge,
          decoration: InputDecoration(
            hintText: tr('Your first name'),
            counterText: '',
          ),
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _cityStep() {
    return FlowStep(
      title: tr('Where are you based?'),
      subtitle: tr('Travelers nearby can meet you before the trip.'),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final city in ProfileSetupScreen.homeCities)
              ChoicePill(
                label: city,
                selected: !_choosingOtherCity && _homeCity == city,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() {
                    _choosingOtherCity = false;
                    _homeCity = city;
                  });
                },
              ),
            ChoicePill(
              key: const ValueKey('setup-other-city'),
              label: tr('Somewhere else'),
              icon: Icons.search_rounded,
              selected: _choosingOtherCity,
              onTap: () {
                unawaited(HapticFeedback.selectionClick());
                setState(() => _choosingOtherCity = true);
              },
            ),
          ],
        ),
        if (_choosingOtherCity) ...[
          const SizedBox(height: AppSpacing.md),
          PlaceField(
            fieldKey: const ValueKey('setup-city-search'),
            controller: _otherCityController,
            label: tr('Home city'),
            icon: Icons.location_city_outlined,
            validator: (_) => null,
            onPicked: (place) => _homeCity = place.label,
          ),
        ],
      ],
    );
  }

  Widget _stylesStep() {
    return FlowStep(
      title: tr('How do you like to travel?'),
      subtitle: tr('Pick a few. We use them to suggest trips.'),
      children: [
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: AppSpacing.sm,
          crossAxisSpacing: AppSpacing.sm,
          childAspectRatio: 1.6,
          children: [
            for (final (style, icon) in ProfileSetupScreen.travelStyles)
              _StyleTile(
                label: tr(style),
                icon: icon,
                selected: _styles.contains(style),
                onTap: () => _toggle(_styles, style, _maxStyles),
              ),
          ],
        ),
      ],
    );
  }

  Widget _languagesStep() {
    return FlowStep(
      title: tr('Which languages do you speak?'),
      subtitle: tr('So your group can plan together easily.'),
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final language in [
              ...ProfileSetupScreen.languages,
              ..._extraLanguages,
            ])
              ChoicePill(
                label: tr(language),
                selected: _languages.contains(language),
                onTap: () => _toggle(_languages, language, _maxLanguages),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('setup-other-language'),
          controller: _otherLanguageController,
          textCapitalization: TextCapitalization.words,
          maxLength: 30,
          decoration: InputDecoration(
            hintText: tr('Another language'),
            counterText: '',
            suffixIcon: IconButton(
              tooltip: tr('Add language'),
              onPressed: _addOtherLanguage,
              icon: const Icon(Icons.add_rounded),
            ),
          ),
          onSubmitted: (_) => _addOtherLanguage(),
        ),
      ],
    );
  }

  Widget _readyStep() {
    final profile = ref.read(appAuthStateProvider).profile;
    return FlowStep(
      title: tr("You're in, {name}!", {'name': _name.split(' ').first}),
      subtitle: tr('Find a trip that fits you, or plan your own.'),
      children: [
        Center(
          child: TweenAnimationBuilder<double>(
            key: ValueKey(_step == _stepCount - 1),
            tween: Tween(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 500),
            curve: Curves.elasticOut,
            builder: (context, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                _AvatarPicker(
                  avatarBytes: _avatarBytes,
                  avatarUrl: profile?.avatarUrl,
                  initials: _name.isEmpty ? '?' : _name[0].toUpperCase(),
                ),
                const Positioned(
                  right: -4,
                  bottom: -4,
                  child: CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.green,
                    child: Icon(Icons.check_rounded, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            if (_homeCity != null)
              Chip(
                avatar: const Icon(Icons.place_outlined, size: 18),
                label: Text(_homeCity!),
              ),
            for (final style in _styles) Chip(label: Text(tr(style))),
            for (final language in _languages) Chip(label: Text(tr(language))),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        Text(
          tr(
            'By continuing you accept the terms of use and privacy policy. CoTravel is a coordination tool, not a travel agency.',
          ),
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.push(AppRoutes.terms),
              child: Text(tr('Read the terms')),
            ),
            TextButton(
              onPressed: () => context.push(AppRoutes.privacy),
              child: Text(tr('Read the privacy policy')),
            ),
          ],
        ),
      ],
    );
  }
}

class _StyleTile extends StatelessWidget {
  const _StyleTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.96,
        duration: const Duration(milliseconds: 180),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? AppColors.greenSoft : AppColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.green : AppColors.border,
              width: selected ? 2 : 1,
            ),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 30, color: AppColors.green),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarPicker extends StatelessWidget {
  const _AvatarPicker({
    required this.avatarBytes,
    required this.avatarUrl,
    required this.initials,
    this.onTap,
  });

  final Uint8List? avatarBytes;
  final String? avatarUrl;
  final String initials;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? image;
    if (avatarBytes != null) {
      image = MemoryImage(avatarBytes!);
    } else if (avatarUrl != null) {
      image = NetworkImage(avatarUrl!);
    }

    final avatar = CircleAvatar(
      radius: 56,
      backgroundColor: AppColors.greenSoft,
      foregroundImage: image,
      child: image == null
          ? Text(
              initials,
              style: Theme.of(
                context,
              ).textTheme.headlineMedium?.copyWith(color: AppColors.green),
            )
          : null,
    );
    if (onTap == null) {
      return avatar;
    }
    return Semantics(
      button: true,
      label: image == null ? tr('Add a photo') : tr('Change photo'),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Column(
          children: [
            avatar,
            const SizedBox(height: AppSpacing.xs),
            Text(
              image == null ? tr('Add a photo') : tr('Change photo'),
              style: const TextStyle(
                color: AppColors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
