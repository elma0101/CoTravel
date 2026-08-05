import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
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
  DateTimeRange? _dateRange;
  String? _travelStyle;
  bool _verifiedOnly = false;

  @override
  void dispose() {
    _originController.dispose();
    _destinationController.dispose();
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
          ),
        );
  }

  void _clearFilters() {
    _originController.clear();
    _destinationController.clear();
    setState(() {
      _dateRange = null;
      _travelStyle = null;
      _verifiedOnly = false;
    });
    ref.read(tripCatalogProvider).clearFilter();
  }

  Future<void> _openFilters() async {
    var nextRange = _dateRange;
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
                      'Refine your search',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year, now.month, now.day),
                          lastDate: DateTime(now.year + 2),
                          initialDateRange: nextRange,
                        );
                        if (picked != null) {
                          setSheetState(() => nextRange = picked);
                        }
                      },
                      icon: const Icon(Icons.date_range_outlined),
                      label: Text(
                        nextRange == null
                            ? 'Choose travel dates'
                            : formatTripDateRange(
                                nextRange!.start,
                                nextRange!.end,
                              ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text(
                      'Travel style',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.xs,
                      children: _travelStyles
                          .map(
                            (style) => ChoiceChip(
                              label: Text(style),
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
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: nextVerified,
                      onChanged: (value) {
                        setSheetState(() => nextVerified = value);
                      },
                      title: const Text('Verified hosts only'),
                      subtitle: const Text(
                        'Show hosts with a linked professional identity.',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Apply filters'),
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
        _dateRange = nextRange;
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
                const SizedBox(height: AppSpacing.xl),
                const _HeroCopy(),
                const SizedBox(height: AppSpacing.lg),
                _TripSearch(
                  originController: _originController,
                  destinationController: _destinationController,
                  hasAdvancedFilters:
                      _dateRange != null ||
                      _travelStyle != null ||
                      _verifiedOnly,
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
                    title: 'Trips are taking a detour',
                    message: catalog.errorMessage!,
                    actionLabel: 'Try again',
                    onAction: catalog.load,
                  )
                else if (trips.isEmpty)
                  _CatalogMessage(
                    icon: Icons.search_off_rounded,
                    title: 'No matching trips',
                    message:
                        'Try a nearby city, a wider date range, or fewer filters.',
                    actionLabel: 'Clear filters',
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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader();

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
        const Spacer(),
        IconButton.filledTonal(
          onPressed: () {},
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_none_rounded),
        ),
      ],
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Find your people,\nthen go.',
          style: Theme.of(context).textTheme.displaySmall,
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Browse clear plans from travelers who value a good fit.',
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _TripSearch extends StatelessWidget {
  const _TripSearch({
    required this.originController,
    required this.destinationController,
    required this.hasAdvancedFilters,
    required this.onSearch,
    required this.onFilters,
  });

  final TextEditingController originController;
  final TextEditingController destinationController;
  final bool hasAdvancedFilters;
  final VoidCallback onSearch;
  final VoidCallback onFilters;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          TextField(
            key: const ValueKey('explore-origin'),
            controller: originController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Leaving from',
              prefixIcon: Icon(Icons.trip_origin_rounded),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('explore-destination'),
            controller: destinationController,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => onSearch(),
            decoration: const InputDecoration(
              hintText: 'Where to?',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              IconButton.outlined(
                onPressed: onFilters,
                tooltip: 'More filters',
                icon: Badge(
                  isLabelVisible: hasAdvancedFilters,
                  child: const Icon(Icons.tune_rounded),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded),
                  label: const Text('Find trips'),
                ),
              ),
            ],
          ),
        ],
      ),
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
            hasFilter ? '$resultCount matching trips' : 'Open trips',
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (hasFilter)
          TextButton(onPressed: onClear, child: const Text('Clear')),
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
