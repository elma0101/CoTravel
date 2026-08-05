import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _emailController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendMagicLink() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);
    final email = _emailController.text.trim();

    try {
      await ref.read(appAuthStateProvider).sendMagicLink(email);
      if (!mounted) {
        return;
      }
      context.go('/check-email?email=${Uri.encodeQueryComponent(email)}');
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_messageFor(error))));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final authState = ref.watch(appAuthStateProvider);

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - AppSpacing.xxl,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _BrandMark(),
                      const Spacer(),
                      Container(
                        width: 76,
                        height: 76,
                        decoration: const BoxDecoration(
                          color: AppColors.greenSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.people_alt_outlined,
                          color: AppColors.green,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        'Travel better,\ntogether.',
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'Create thoughtful trips, meet compatible travelers, and keep every plan in one place.',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                      ),
                      const Spacer(),
                      if (authState.hasBackend) ...[
                        Form(
                          key: _formKey,
                          child: TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.email],
                            autocorrect: false,
                            decoration: const InputDecoration(
                              labelText: 'Email address',
                              hintText: 'you@example.com',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) {
                              final email = value?.trim() ?? '';
                              if (!RegExp(
                                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                              ).hasMatch(email)) {
                                return 'Enter a valid email address';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) => _sendMagicLink(),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        FilledButton.icon(
                          onPressed: _isSubmitting ? null : _sendMagicLink,
                          icon: _isSubmitting
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.arrow_forward_rounded),
                          label: Text(
                            _isSubmitting
                                ? 'Sending link…'
                                : 'Continue by email',
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'We will email you a secure sign-in link. No password needed.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                      ],
                      if (config.previewAuthEnabled) ...[
                        if (authState.hasBackend)
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: AppSpacing.sm,
                            ),
                            child: Row(
                              children: [
                                Expanded(child: Divider()),
                                Padding(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                  ),
                                  child: Text('development'),
                                ),
                                Expanded(child: Divider()),
                              ],
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: authState.signInForPreview,
                          icon: const Icon(Icons.visibility_outlined),
                          label: const Text('Preview the app'),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  String _messageFor(Object error) {
    final message = error.toString();
    return message.startsWith('AuthException: ')
        ? message.substring('AuthException: '.length)
        : 'We could not send the link. Please try again.';
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.green,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.route_rounded, color: Colors.white, size: 22),
        ),
        const SizedBox(width: AppSpacing.sm),
        Text('CoTravel', style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }
}
