import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/l10n/app_strings.dart';
import '../../trips/domain/trip.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../../trips/presentation/widgets/trip_card.dart';

class ExploreScreen extends ConsumerStatefulWidget {
  const ExploreScreen({super.key});

  @override
  ConsumerState<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends ConsumerState<ExploreScreen> {
  static const _travelStyles = [
    'Culture',
    'Food',
    'Nature',
    'Road trips',
    'Budget',
    'Remote work',
  ];

  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _hostBackgroundController = TextEditingController();
  DateTimeRange? _dateRange;
  String? _travelStyle;
  bool _verifiedOnly = false;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
    _hostBackgroundController.dispose();
    super.dispose();
  }

  void _applyFilters() {
    FocusScope.of(context).unfocus();
    ref
        .read(tripCatalogProvider)
        .applyFilter(
          TripFilter(
            originQuery: _originController.text,
            destinationQuery: _destinationController.text,
            startDate: _dateRange?.start,
            endDate: _dateRange?.end,
            travelStyle: _travelStyle,
            verifiedHostsOnly: _verifiedOnly,
            hostBackgroundQuery: _hostBackgroundController.text,
          ),
        );
  }

  void _clearFilters() {
    _originController.clear();
    _destinationController.clear();
    _hostBackgroundController.clear();
    setState(() {
      _dateRange = null;
      _travelStyle = null;
      _verifiedOnly = false;
    });
    ref.read(tripCatalogProvider).clearFilter();
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (picked != null && mounted) {
      setState(() => _dateRange = picked);
    }
  }

  Future<void> _openFilters() async {
    var nextStyle = _travelStyle;
    var nextVerified = _verifiedOnly;

    final shouldApply = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      tr('Refine your search'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      key: const ValueKey('explore-origin'),
                      controller: _originController,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        hintText: tr('Leaving from'),
                        prefixIcon: Icon(Icons.trip_origin_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      tr('Travel style'),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: _travelStyles
                          .map(
                            (style) => ChoiceChip(
                              label: Text(tr(style)),
                              selected: nextStyle == style,
                              onSelected: (selected) {
                                setSheetState(
                                  () => nextStyle = selected ? style : null,
                                );
                              },
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      key: const ValueKey('explore-host-background'),
                      controller: _hostBackgroundController,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        labelText: tr('Host background'),
                        hintText: tr('Designer, teacher, engineer…'),
                        helperText: tr('Declared by hosts and not checked.'),
                        prefixIcon: const Icon(Icons.work_outline_rounded),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: nextVerified,
                      onChanged: (value) {
                        setSheetState(() => nextVerified = value);
                      },
                      title: Text(tr('Verified hosts only')),
                      subtitle: Text(
                        tr('Show hosts with a linked professional identity.'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(tr('Apply filters')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (shouldApply == true && mounted) {
      setState(() {
        _travelStyle = nextStyle;
        _verifiedOnly = nextVerified;
      });
      _applyFilters();
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);

    return SafeArea(
      child: ListenableBuilder(
        listenable: catalog,
        builder: (context, child) {
          final trips = catalog.discoverableTrips;
          return RefreshIndicator(
            onRefresh: catalog.load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                const _BrandHeader(),
                const SizedBox(height: AppSpacing.lg),
                const _HeroCopy(),
                const SizedBox(height: AppSpacing.md),
                _TripSearch(
                  destinationController: _destinationController,
                  dateRange: _dateRange,
                  hasAdvancedFilters:
                      _originController.text.trim().isNotEmpty ||
                      _hostBackgroundController.text.trim().isNotEmpty ||
                      _travelStyle != null ||
                      _verifiedOnly,
                  onPickDates: _pickDates,
                  onSearch: _applyFilters,
                  onFilters: _openFilters,
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionHeading(
                  resultCount: trips.length,
                  hasFilter: catalog.filter.isActive,
                  onClear: _clearFilters,
                ),
                const SizedBox(height: AppSpacing.md),
                if (catalog.isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (catalog.errorMessage != null)
                  _CatalogMessage(
                    icon: Icons.cloud_off_outlined,
                    title: tr('Trips are taking a detour'),
                    message: catalog.errorMessage!,
                    actionLabel: tr('Try again'),
                    onAction: catalog.load,
                  )
                else if (trips.isEmpty)
                  _CatalogMessage(
                    icon: Icons.search_off_rounded,
                    title: tr('No matching trips'),
                    message: tr(
                      'Try a nearby city, a wider date range, or fewer filters.',
                    ),
                    actionLabel: tr('Clear filters'),
                    onAction: _clearFilters,
                  )
                else
                  for (var index = 0; index < trips.length; index++) ...[
                    TripCard(
                      trip: trips[index],
                      onTap: () =>
                          context.push(AppRoutes.tripDetails(trips[index].id)),
                    ),
                    if (index != trips.length - 1)
                      const SizedBox(height: AppSpacing.md),
                  ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BrandHeader extends ConsumerWidget {
  const _BrandHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationControllerProvider);
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
        const Spacer(),
        ListenableBuilder(
          listenable: notifications,
          builder: (context, child) {
            final unread = notifications.unreadCount;
            return IconButton.filledTonal(
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

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return Text(
      tr('Find your people, then go.'),
      style: Theme.of(context).textTheme.headlineMedium,
    );
  }
}

class _TripSearch extends StatelessWidget {
  const _TripSearch({
    required this.destinationController,
    required this.dateRange,
    required this.hasAdvancedFilters,
    required this.onPickDates,
    required this.onSearch,
    required this.onFilters,
  });

  final TextEditingController destinationController;
  final DateTimeRange? dateRange;
  final bool hasAdvancedFilters;
  final VoidCallback onPickDates;
  final VoidCallback onSearch;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    final range = dateRange;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              TextField(
                key: const ValueKey('explore-destination'),
                controller: destinationController,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.search,
                onSubmitted: (_) => onSearch(),
                decoration: InputDecoration(
                  labelText: tr('Destination'),
                  hintText: tr('Anywhere'),
                  floatingLabelBehavior: FloatingLabelBehavior.always,
                  prefixIcon: Icon(Icons.location_on_outlined),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
              ),
              const Divider(indent: AppSpacing.md, endIndent: AppSpacing.md),
              InkWell(
                key: const ValueKey('explore-dates'),
                onTap: onPickDates,
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    0,
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 48,
                        child: Icon(
                          Icons.calendar_today_outlined,
                          color: AppColors.muted,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xxs),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr('Dates'),
                              style: textTheme.bodySmall?.copyWith(
                                color: AppColors.muted,
                              ),
                            ),
                            Text(
                              range == null
                                  ? tr('Any dates')
                                  : formatTripDateRange(range.start, range.end),
                              style: textTheme.bodyLarge,
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.muted,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            IconButton.outlined(
              onPressed: onFilters,
              tooltip: tr('More filters'),
              icon: Badge(
                isLabelVisible: hasAdvancedFilters,
                child: const Icon(Icons.tune_rounded),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: ElevatedButton(
                onPressed: onSearch,
                child: Text(tr('Search open trips')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.resultCount,
    required this.hasFilter,
    required this.onClear,
  });

  final int resultCount;
  final bool hasFilter;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            hasFilter
                ? tr('{resultCount} matching trips', {
                    'resultCount': resultCount,
                  })
                : tr('Open trips'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        TextButton.icon(
          key: const ValueKey('open-trip-map'),
          onPressed: () => context.push(AppRoutes.tripMap),
          icon: const Icon(Icons.map_outlined, size: 18),
          label: Text(tr('Map')),
        ),
        if (hasFilter) TextButton(onPressed: onClear, child: Text(tr('Clear'))),
      ],
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
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppColors.green),
          const SizedBox(height: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}
