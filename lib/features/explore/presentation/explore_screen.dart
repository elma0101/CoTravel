import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/step_flow.dart';
import '../../profile/presentation/linkedin_gate.dart';
import '../../trips/application/trip_catalog_controller.dart';
import '../../trips/domain/trip.dart';
import '../../trips/presentation/plan_trip_screen.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../../trips/presentation/widgets/trip_card.dart';
import 'widgets/trip_swipe_deck.dart';

/// Discovery: swipeable trip cards, or a list, with filter chips that apply
/// as soon as they are tapped.
class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

enum _DateChoice { thisWeekend, nextTwoWeeks, thisMonth, custom }

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  bool _showList = false;
  _DateChoice? _dateChoice;

  TripCatalogController get _catalog => ref.read(tripCatalogProvider);
  TripFilter get _filter => _catalog.filter;

  void _apply(TripFilter filter) {
    unawaited(HapticFeedback.selectionClick());
    _catalog.applyFilter(filter);
  }

  void _clearFilters() {
    setState(() => _dateChoice = null);
    _catalog.clearFilter();
  }

  /// The filter without dates. copyWith cannot clear a date.
  TripFilter _withDates(DateTime? start, DateTime? end) {
    final filter = _filter;
    return TripFilter(
      originQuery: filter.originQuery,
      destinationQuery: filter.destinationQuery,
      startDate: start,
      endDate: end,
      travelStyle: filter.travelStyle,
      verifiedHostsOnly: filter.verifiedHostsOnly,
      hostBackgroundQuery: filter.hostBackgroundQuery,
    );
  }

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _chooseDestination() async {
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) =>
          _DestinationSheet(current: _filter.destinationQuery),
    );
    if (chosen != null && mounted) {
      _apply(_filter.copyWith(destinationQuery: chosen));
    }
  }

  Future<void> _chooseDates() async {
    final choice = await showModalBottomSheet<_DateChoice?>(
      context: context,
      showDragHandle: true,
      builder: (context) => _SheetLayout(
        title: tr('When?'),
        children: [
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              for (final (choice, label) in [
                (_DateChoice.thisWeekend, tr('This weekend')),
                (_DateChoice.nextTwoWeeks, tr('Next two weeks')),
                (_DateChoice.thisMonth, tr('Next 30 days')),
              ])
                ChoicePill(
                  label: label,
                  selected: _dateChoice == choice,
                  onTap: () => Navigator.pop(context, choice),
                ),
              ChoicePill(
                label: tr('Choose dates'),
                icon: Icons.edit_calendar_outlined,
                selected: _dateChoice == _DateChoice.custom,
                onTap: () => Navigator.pop(context, _DateChoice.custom),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: Text(tr('Any dates')),
            ),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    final today = _today;
    DateTimeRange? range;
    switch (choice) {
      case _DateChoice.thisWeekend:
        final friday = today.add(
          Duration(days: (DateTime.friday - today.weekday) % 7),
        );
        // From today when the weekend has already started.
        final start = today.weekday >= DateTime.friday ? today : friday;
        range = DateTimeRange(
          start: start,
          end: friday.add(const Duration(days: 2)),
        );
      case _DateChoice.nextTwoWeeks:
        range = DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 14)),
        );
      case _DateChoice.thisMonth:
        range = DateTimeRange(
          start: today,
          end: today.add(const Duration(days: 30)),
        );
      case _DateChoice.custom:
        range = await showDateRangePicker(
          context: context,
          firstDate: today,
          lastDate: DateTime(today.year + 2),
        );
        if (range == null || !mounted) {
          return;
        }
      case null:
        range = null;
    }
    setState(() => _dateChoice = choice);
    _apply(_withDates(range?.start, range?.end));
  }

  Future<void> _openMoreFilters() async {
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _MoreFiltersSheet(
        origin: _filter.originQuery,
        background: _filter.hostBackgroundQuery,
      ),
    );
    if (result != null && mounted) {
      _apply(
        _filter.copyWith(
          originQuery: result.$1,
          hostBackgroundQuery: result.$2,
        ),
      );
    }
  }

  void _toggleStyle(String style) {
    _apply(
      _filter.travelStyle == style
          ? _filter.copyWith(clearTravelStyle: true)
          : _filter.copyWith(travelStyle: style),
    );
  }

  void _openTrip(Trip trip) {
    unawaited(context.push(AppRoutes.tripDetails(trip.id)));
  }

  Future<void> _saveTrip(Trip trip) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _catalog.toggleSaved(trip);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(tr('Saved. Find it in My trips.')),
          ),
        );
    } on Object {
      messenger.showSnackBar(
        SnackBar(content: Text(tr('The trip could not be saved. Try again.'))),
      );
    }
  }

  Future<void> _planOwnTrip() async {
    final verified = await ensureLinkedInVerified(
      context,
      ref,
      reason: LinkedInGateReason.host,
    );
    if (verified && mounted) {
      unawaited(context.push(AppRoutes.createTrip));
    }
  }

  String get _datesLabel {
    final filter = _filter;
    return switch (_dateChoice) {
      _DateChoice.thisWeekend => tr('This weekend'),
      _DateChoice.nextTwoWeeks => tr('Next two weeks'),
      _DateChoice.thisMonth => tr('Next 30 days'),
      _ when filter.startDate != null && filter.endDate != null =>
        formatTripDateRange(filter.startDate!, filter.endDate!),
      _ => tr('Any dates'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);

    return SafeArea(
      child: ListenableBuilder(
        listenable: catalog,
        builder: (context, child) {
          final trips = catalog.discoverableTrips;
          final filter = catalog.filter;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.md,
                  0,
                ),
                child: _Header(
                  showList: _showList,
                  onToggleView: () {
                    unawaited(HapticFeedback.selectionClick());
                    setState(() => _showList = !_showList);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 48,
                child: ListView(
                  key: const ValueKey('explore-filter-chips'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  children: [
                    _FilterChip(
                      key: const ValueKey('filter-destination'),
                      icon: Icons.location_on_outlined,
                      label: filter.destinationQuery.trim().isEmpty
                          ? tr('Anywhere')
                          : filter.destinationQuery.trim(),
                      active: filter.destinationQuery.trim().isNotEmpty,
                      dropdown: true,
                      onTap: _chooseDestination,
                    ),
                    _FilterChip(
                      key: const ValueKey('filter-dates'),
                      icon: Icons.calendar_today_outlined,
                      label: _datesLabel,
                      active: filter.startDate != null,
                      dropdown: true,
                      onTap: _chooseDates,
                    ),
                    _FilterChip(
                      key: const ValueKey('filter-verified'),
                      icon: Icons.verified_outlined,
                      label: tr('Verified hosts'),
                      active: filter.verifiedHostsOnly,
                      onTap: () => _apply(
                        filter.copyWith(
                          verifiedHostsOnly: !filter.verifiedHostsOnly,
                        ),
                      ),
                    ),
                    for (final style in PlanTripScreen.travelStyles)
                      _FilterChip(
                        label: tr(style),
                        active: filter.travelStyle == style,
                        onTap: () => _toggleStyle(style),
                      ),
                    _FilterChip(
                      key: const ValueKey('filter-more'),
                      icon: Icons.tune_rounded,
                      label: tr('More'),
                      active:
                          filter.originQuery.trim().isNotEmpty ||
                          filter.hostBackgroundQuery.trim().isNotEmpty,
                      onTap: _openMoreFilters,
                    ),
                    if (filter.isActive)
                      Padding(
                        padding: const EdgeInsets.only(left: AppSpacing.xs),
                        child: TextButton(
                          key: const ValueKey('filter-clear'),
                          onPressed: _clearFilters,
                          child: Text(tr('Clear')),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(child: _body(catalog, trips)),
            ],
          );
        },
      ),
    );
  }

  Widget _body(TripCatalogController catalog, List<Trip> trips) {
    if (catalog.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (catalog.errorMessage != null) {
      return _CatalogMessage(
        icon: Icons.cloud_off_outlined,
        title: tr('Trips are taking a detour'),
        message: catalog.errorMessage!,
        actionLabel: tr('Try again'),
        onAction: catalog.load,
      );
    }
    if (trips.isEmpty) {
      return _CatalogMessage(
        icon: Icons.search_off_rounded,
        title: catalog.filter.isActive
            ? tr('No matching trips')
            : tr('No open trips yet'),
        message: catalog.filter.isActive
            ? tr('Try a nearby city, a wider date range, or fewer filters.')
            : tr('Be the first: plan a trip and others can join you.'),
        actionLabel: catalog.filter.isActive
            ? tr('Clear filters')
            : tr('Plan a new trip'),
        onAction: catalog.filter.isActive ? _clearFilters : _planOwnTrip,
      );
    }
    if (_showList) {
      return RefreshIndicator(
        onRefresh: catalog.load,
        child: ListView.separated(
          key: const ValueKey('explore-list'),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          itemCount: trips.length,
          separatorBuilder: (context, index) =>
              const SizedBox(height: AppSpacing.md),
          itemBuilder: (context, index) => TripCard(
            trip: trips[index],
            onTap: () => _openTrip(trips[index]),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TripSwipeDeck(
        trips: trips,
        isSaved: (trip) => catalog.isSaved(trip.id),
        onOpen: _openTrip,
        onSave: _saveTrip,
        emptyState: (startOver) => _CatalogMessage(
          icon: Icons.travel_explore_rounded,
          title: tr('You have seen every trip'),
          message: tr(
            'Saved trips wait for you in My trips. New trips appear here as hosts publish them.',
          ),
          actionLabel: tr('Start over'),
          onAction: startOver,
          secondaryLabel: tr('Plan your own trip'),
          onSecondary: _planOwnTrip,
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.showList, required this.onToggleView});

  final bool showList;
  final VoidCallback onToggleView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationControllerProvider);
    return Row(
      children: [
        Expanded(
          child: Text(
            tr('Find your people, then go.'),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        IconButton(
          key: const ValueKey('explore-toggle-view'),
          tooltip: showList ? tr('Show as cards') : tr('Show as a list'),
          onPressed: onToggleView,
          icon: Icon(
            showList ? Icons.style_outlined : Icons.view_agenda_outlined,
          ),
        ),
        IconButton(
          key: const ValueKey('open-trip-map'),
          tooltip: tr('Map'),
          onPressed: () => context.push(AppRoutes.tripMap),
          icon: const Icon(Icons.map_outlined),
        ),
        ListenableBuilder(
          listenable: notifications,
          builder: (context, child) {
            final unread = notifications.unreadCount;
            return IconButton(
              key: const ValueKey('open-notifications'),
              onPressed: () => context.push(AppRoutes.notifications),
              tooltip: unread == 0
                  ? tr('Notifications')
                  : tr('Notifications, {unread} unread', {'unread': unread}),
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.notifications_none_rounded),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
    this.dropdown = false,
    super.key,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;
  final bool dropdown;

  @override
  Widget build(BuildContext context) {
    final foreground = active ? Colors.white : AppColors.ink;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: Semantics(
        button: true,
        selected: active,
        child: Material(
          color: active ? AppColors.green : AppColors.surface,
          shape: StadiumBorder(
            side: BorderSide(
              color: active ? AppColors.green : AppColors.border,
            ),
          ),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18, color: foreground),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (dropdown)
                    Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: foreground,
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

class _DestinationSheet extends StatefulWidget {
  const _DestinationSheet({required this.current});

  final String current;

  @override
  State<_DestinationSheet> createState() => _DestinationSheetState();
}

class _DestinationSheetState extends State<_DestinationSheet> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetLayout(
      title: tr('Where to?'),
      children: [
        TextField(
          key: const ValueKey('explore-destination'),
          controller: _controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: tr('Search a place'),
            prefixIcon: const Icon(Icons.search_rounded),
          ),
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final place in PlanTripScreen.popularDestinations)
              ChoicePill(
                label: place,
                selected: widget.current == place,
                onTap: () => Navigator.pop(context, place),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            TextButton(
              onPressed: () => Navigator.pop(context, ''),
              child: Text(tr('Anywhere')),
            ),
            const Spacer(),
            FilledButton(
              key: const ValueKey('explore-destination-apply'),
              onPressed: () => Navigator.pop(context, _controller.text.trim()),
              child: Text(tr('Show trips')),
            ),
          ],
        ),
      ],
    );
  }
}

class _MoreFiltersSheet extends StatefulWidget {
  const _MoreFiltersSheet({required this.origin, required this.background});

  final String origin;
  final String background;

  @override
  State<_MoreFiltersSheet> createState() => _MoreFiltersSheetState();
}

class _MoreFiltersSheetState extends State<_MoreFiltersSheet> {
  late final _origin = TextEditingController(text: widget.origin);
  late final _background = TextEditingController(text: widget.background);

  @override
  void dispose() {
    _origin.dispose();
    _background.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SheetLayout(
      title: tr('More filters'),
      children: [
        TextField(
          key: const ValueKey('explore-origin'),
          controller: _origin,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: tr('Leaving from'),
            prefixIcon: const Icon(Icons.trip_origin_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          key: const ValueKey('explore-host-background'),
          controller: _background,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: tr('Host background'),
            hintText: tr('Designer, teacher, engineer…'),
            helperText: tr('Declared by hosts and not checked.'),
            prefixIcon: const Icon(Icons.work_outline_rounded),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton(
          onPressed: () => Navigator.pop(context, (
            _origin.text.trim(),
            _background.text.trim(),
          )),
          child: Text(tr('Apply filters')),
        ),
      ],
    );
  }
}

class _SheetLayout extends StatelessWidget {
  const _SheetLayout({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.md),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.green),
            const SizedBox(height: AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
            if (secondaryLabel != null)
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
          ],
        ),
      ),
    );
  }
}
