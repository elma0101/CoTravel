import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'providers/app_providers.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatControllerProvider);
    return ListenableBuilder(
      listenable: chat,
      builder: (context, child) {
        final unreadCount = chat.totalUnreadCount;
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) {
              navigationShell.goBranch(
                index,
                initialLocation: index == navigationShell.currentIndex,
              );
            },
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.explore_outlined),
                selectedIcon: Icon(Icons.explore),
                label: 'Explore',
              ),
              const NavigationDestination(
                icon: Icon(Icons.luggage_outlined),
                selectedIcon: Icon(Icons.luggage),
                label: 'My trips',
              ),
              NavigationDestination(
                icon: _UnreadIcon(
                  count: unreadCount,
                  child: const Icon(Icons.chat_bubble_outline_rounded),
                ),
                selectedIcon: _UnreadIcon(
                  count: unreadCount,
                  child: const Icon(Icons.chat_bubble_rounded),
                ),
                label: 'Messages',
              ),
              const NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Profile',
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UnreadIcon extends StatelessWidget {
  const _UnreadIcon({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      label: Text(count > 99 ? '99+' : '$count'),
      child: child,
    );
  }
}
