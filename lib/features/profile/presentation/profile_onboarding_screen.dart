import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../domain/user_profile.dart';

class ProfileOnboardingScreen extends ConsumerStatefulWidget {
  const ProfileOnboardingScreen({super.key});

  @override
  ConsumerState<ProfileOnboardingScreen> createState() =>
      _ProfileOnboardingScreenState();
}

class _ProfileOnboardingScreenState
    extends ConsumerState<ProfileOnboardingScreen> {
  static const _availableStyles = [
    'Culture',
    'Food',
    'Nature',
    'Road trips',
    'Budget',
    'Remote work',
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _bioController = TextEditingController();
  final _cityController = TextEditingController();
  final _languagesController = TextEditingController();
  final _imagePicker = ImagePicker();
  final _selectedStyles = <String>{};

  Uint8List? _avatarBytes;
  String _avatarExtension = 'jpg';
  bool _isSaving = false;
  bool _isLinking = false;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appAuthStateProvider).profile;
    if (profile != null) {
      _nameController.text = profile.displayName ?? '';
      _bioController.text = profile.bio ?? '';
      _cityController.text = profile.homeCity ?? '';
      _languagesController.text = profile.languages.join(', ');
      _selectedStyles.addAll(profile.travelStyles);
    }
    unawaited(_restoreLostImage());
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    _cityController.dispose();
    _languagesController.dispose();
    super.dispose();
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

  Future<void> _linkLinkedIn() async {
    setState(() => _isLinking = true);
    try {
      final launched = await ref.read(appAuthStateProvider).linkLinkedIn();
      if (!launched && mounted) {
        _showMessage('LinkedIn could not be opened. Please try again.');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
      }
    } finally {
      if (mounted) {
        setState(() => _isLinking = false);
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_selectedStyles.isEmpty) {
      _showMessage('Choose at least one travel style.');
      return;
    }

    final languages = _languagesController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet()
        .take(8)
        .toList();
    if (languages.isEmpty) {
      _showMessage('Add at least one language.');
      return;
    }

    final config = ref.read(appConfigProvider);
    final profile = ref.read(appAuthStateProvider).profile;
    if (config.requireLinkedInVerification &&
        profile?.isLinkedInVerified != true) {
      _showMessage('Connect LinkedIn before completing your profile.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ref
          .read(appAuthStateProvider)
          .completeProfile(
            draft: ProfileDraft(
              displayName: _nameController.text.trim(),
              bio: _bioController.text.trim(),
              homeCity: _cityController.text.trim(),
              travelStyles: _selectedStyles.toList(),
              languages: languages,
            ),
            avatarBytes: _avatarBytes,
            avatarExtension: _avatarExtension,
          );
    } on Object catch (error) {
      if (mounted) {
        _showMessage(_messageFor(error));
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
    final config = ref.watch(appConfigProvider);
    final profile = authState.profile;
    final isVerified = profile?.isLinkedInVerified == true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your travel profile'),
        actions: [
          TextButton(
            onPressed: authState.signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xl,
            ),
            children: [
              Text(
                'Help people know who they will travel with.',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Keep it brief, honest, and useful. You can edit these details later.',
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.xl),
              Center(
                child: _AvatarEditor(
                  profile: profile,
                  avatarBytes: _avatarBytes,
                  onTap: _pickAvatar,
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Display name'),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length < 2 || length > 60
                      ? 'Use between 2 and 60 characters'
                      : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _bioController,
                minLines: 3,
                maxLines: 5,
                maxLength: 280,
                decoration: const InputDecoration(
                  labelText: 'Short introduction',
                  hintText: 'What makes you a good travel companion?',
                ),
                validator: (value) {
                  final length = value?.trim().length ?? 0;
                  return length < 20 ? 'Write at least 20 characters' : null;
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _cityController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Home city',
                  prefixIcon: Icon(Icons.location_city_outlined),
                ),
                validator: (value) => (value?.trim().isEmpty ?? true)
                    ? 'Add your home city'
                    : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Travel styles',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: _availableStyles.map((style) {
                  return FilterChip(
                    label: Text(style),
                    selected: _selectedStyles.contains(style),
                    onSelected: (selected) {
                      setState(() {
                        if (selected && _selectedStyles.length < 5) {
                          _selectedStyles.add(style);
                        } else if (!selected) {
                          _selectedStyles.remove(style);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _languagesController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Languages',
                  hintText: 'Arabic, French, English',
                  helperText: 'Separate languages with commas',
                ),
              ),
              const SizedBox(height: AppSpacing.xl),
              _VerificationCard(
                isVerified: isVerified,
                isRequired: config.requireLinkedInVerification,
                isLinking: _isLinking,
                onLink: _linkLinkedIn,
                onRefresh: authState.refreshProfile,
              ),
              const SizedBox(height: AppSpacing.xl),
              FilledButton(
                onPressed: _isSaving ? null : _saveProfile,
                child: Text(_isSaving ? 'Saving profile…' : 'Complete profile'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String _messageFor(Object error) {
    final value = error.toString();
    for (final prefix in [
      'AuthException: ',
      'PostgrestException: ',
      'StorageException: ',
    ]) {
      if (value.startsWith(prefix)) {
        return value.substring(prefix.length);
      }
    }
    return 'Something went wrong. Please try again.';
  }
}

class _AvatarEditor extends StatelessWidget {
  const _AvatarEditor({
    required this.profile,
    required this.avatarBytes,
    required this.onTap,
  });

  final UserProfile? profile;
  final Uint8List? avatarBytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    ImageProvider<Object>? image;
    if (avatarBytes != null) {
      image = MemoryImage(avatarBytes!);
    } else if (profile?.avatarUrl != null) {
      image = NetworkImage(profile!.avatarUrl!);
    }

    return Semantics(
      button: true,
      label: 'Choose profile photo',
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Stack(
          children: [
            CircleAvatar(
              radius: 52,
              backgroundColor: AppColors.greenSoft,
              foregroundImage: image,
              child: image == null
                  ? Text(
                      profile?.initials ?? '?',
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(color: AppColors.green),
                    )
                  : null,
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.canvas, width: 3),
                ),
                child: const Icon(
                  Icons.add_a_photo_outlined,
                  color: Colors.white,
                  size: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.isVerified,
    required this.isRequired,
    required this.isLinking,
    required this.onLink,
    required this.onRefresh,
  });

  final bool isVerified;
  final bool isRequired;
  final bool isLinking;
  final VoidCallback onLink;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: isVerified ? AppColors.greenSoft : AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isVerified ? AppColors.green : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isVerified ? Icons.verified_rounded : Icons.badge_outlined,
                color: AppColors.green,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  isVerified ? 'LinkedIn verified' : 'Verify with LinkedIn',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (isRequired && !isVerified)
                const Text(
                  'Required',
                  style: TextStyle(
                    color: AppColors.terracotta,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            isVerified
                ? 'Your professional identity is connected.'
                : 'This gives future companions a simple trust signal. CoTravel never posts to LinkedIn.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          if (!isVerified) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isLinking ? null : onLink,
                    child: Text(isLinking ? 'Opening…' : 'Connect LinkedIn'),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                IconButton(
                  onPressed: onRefresh,
                  tooltip: 'Refresh verification',
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
