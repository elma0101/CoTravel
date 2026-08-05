import 'package:flutter/material.dart';

import '../../core/widgets/app_async_views.dart';
import '../auth/app_auth_state.dart';

class StartupScreen extends StatelessWidget {
  const StartupScreen({required this.authState, super.key});

  final AppAuthState authState;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: authState,
          builder: (context, child) {
            if (authState.status == AppSessionStatus.failure) {
              return AppErrorView(
                title: 'We could not load your account',
                message:
                    authState.errorMessage ?? 'Please check your connection.',
                onRetry: authState.refreshProfile,
              );
            }

            return const AppLoadingView(
              message: 'Preparing your next journey…',
            );
          },
        ),
      ),
    );
  }
}
