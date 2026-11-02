import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/analytics/product_analytics.dart';
import '../../../core/l10n/app_strings.dart';
import '../../../core/widgets/step_flow.dart';
import '../application/trip_catalog_controller.dart';
import '../data/place_search.dart';
import '../domain/trip.dart';
import 'trip_formatters.dart';
import 'widgets/place_field.dart';
import 'widgets/trip_card.dart';
import 'widgets/trip_photos_editor.dart';

/// Planning a new trip as a few full-screen questions: route, dates, group,
/// budget, then a preview to publish. Stop types, travel modes and notes are
/// left for Edit trip, so a simple trip needs only its destination typed.
class PlanTripScreen extends ConsumerStatefulWidget {
  const PlanTripScreen({super.key});

  static const popularDestinations = [
    'Merzouga',
    'Chefchaouen',
    'Essaouira',
    'Imlil',
    'Ouarzazate',
    'Taghazout',
    'Dakhla',
  ];

  static const travelStyles = [
    'Culture',
    'Food',
    'Nature',
    'Road trips',
    'Budget',
    'Remote work',
  ];

  static const currencies = ['MAD', 'EUR', 'USD'];

  @override
  ConsumerState<PlanTripScreen> createState() => _PlanTripScreenState();
}

enum _DatePreset { nextWeekend, weekendAfter, longWeekend, custom }

class _PlanTripScreenState extends ConsumerState<PlanTripScreen> {
  static const _stepCount = 5;
  static const _maxStops = 8;
  static const _minCapacity = 2;
  static const _maxCapacity = 12;

  final _pageController = PageController();
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();
  final _titleController = TextEditingController();
  final _summaryController = TextEditingController();
  final _viaStops = <_ViaStop>[];
  final _imagePicker = ImagePicker();
  final _photos = <NewTripPhoto>[];

  int _step = 0;
  PlaceSuggestion? _pickedOrigin;
  PlaceSuggestion? _pickedDestination;
  late DateTimeRange _dates;
  _DatePreset _datePreset = _DatePreset.nextWeekend;
  int _capacity = 4;
  double _lodgingPerPerson = 400;
  double _transportPerPerson = 200;
  String _currency = PlanTripScreen.currencies.first;
  String _travelStyle = PlanTripScreen.travelStyles.first;
  bool _titleEdited = false;
  bool _summaryEdited = false;
  Trip? _published;

  @override
  void initState() {
    super.initState();
    final profile = ref.read(appAuthStateProvider).profile;
    _originController.text = profile?.homeCity ?? '';
    final style = profile?.travelStyles.firstOrNull;
    if (style != null && PlanTripScreen.travelStyles.contains(style)) {
      _travelStyle = style;
    }
    _dates = _rangeFor(_DatePreset.nextWeekend);
    for (final controller in [_originController, _destinationController]) {
      controller.addListener(_refresh);
    }
    unawaited(
      ref.read(productAnalyticsProvider).track(ProductEvent.tripBuilderOpened),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _titleController.dispose();
    _summaryController.dispose();
    for (final stop in _viaStops) {
      stop.dispose();
    }
    super.dispose();
  }

  void _refresh() => setState(() {});

  // Dates

  static DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTimeRange _rangeFor(_DatePreset preset) {
    final today = _today;
    final friday = today.add(
      Duration(days: (DateTime.friday - today.weekday) % 7),
    );
    return switch (preset) {
      _DatePreset.nextWeekend || _DatePreset.custom => DateTimeRange(
        start: friday,
        end: friday.add(const Duration(days: 2)),
      ),
      _DatePreset.weekendAfter => DateTimeRange(
        start: friday.add(const Duration(days: 7)),
        end: friday.add(const Duration(days: 9)),
      ),
      _DatePreset.longWeekend => DateTimeRange(
        start: friday,
        end: friday.add(const Duration(days: 3)),
      ),
    };
  }

  void _choosePreset(_DatePreset preset) {
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _datePreset = preset;
      _dates = _rangeFor(preset);
    });
  }

  Future<void> _pickDates() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: _today,
      lastDate: DateTime(_today.year + 2),
      initialDateRange: _dates,
    );
    if (picked != null) {
      setState(() {
        _datePreset = _DatePreset.custom;
        _dates = DateTimeRange(start: picked.start, end: picked.end);
      });
    }
  }

  int get _days => _dates.end.difference(_dates.start).inDays + 1;

  // Route

  String get _origin => _originController.text.trim();
  String get _destination => _destinationController.text.trim();

  void _addViaStop() {
    if (_viaStops.length >= _maxStops - 1) {
      return;
    }
    setState(() => _viaStops.add(_ViaStop()..controller.addListener(_refresh)));
  }

  void _removeViaStop(int index) {
    setState(() => _viaStops.removeAt(index).dispose());
  }

  void _chooseDestination(String place) {
    unawaited(HapticFeedback.selectionClick());
    _pickedDestination = null;
    _destinationController.text = place;
  }

  /// The stops in order, the destination last. Arrival days are spread over
  /// the trip; the host can change them later in Edit trip.
  List<TripStop> get _stops {
    final places = [
      for (final stop in _viaStops)
        if (stop.label.length >= 2) (stop.label, stop.picked),
      (_destination, _pickedDestination),
    ];
    final span = _days - 1;
    return [
      for (var index = 0; index < places.length; index++)
        _stopAt(
          places[index].$1,
          places[index].$2,
          _dates.start.add(Duration(days: span * index ~/ places.length)),
        ),
    ];
  }

  TripStop _stopAt(String label, PlaceSuggestion? picked, DateTime arrival) {
    final point = picked?.label == label ? picked!.coordinate : null;
    return TripStop(
      city: label,
      arrivalDate: arrival,
      latitude: point?.latitude,
      longitude: point?.longitude,
    );
  }

  // Budget

  double get _perPerson => _lodgingPerPerson + _transportPerPerson;

  // Title and summary

  static String _shortPlace(String label) => label.split(',').first.trim();

  String get _suggestedTitle {
    final place = _shortPlace(_destination);
    final includesSaturday = List.generate(
      _days,
      (offset) => _dates.start.add(Duration(days: offset)).weekday,
    ).contains(DateTime.saturday);
    final title = _days <= 3 && includesSaturday
        ? tr('Weekend in {place}', {'place': place})
        : _days == 4 && includesSaturday
        ? tr('Long weekend in {place}', {'place': place})
        : trPlural(_days, '{n} day in {place}', '{n} days in {place}', {
            'place': place,
          });
    return title.length > 80 ? title.substring(0, 80).trim() : title;
  }

  String get _suggestedSummary {
    return trPlural(
      _days,
      'A day trip from {origin} to {destination}, with a taste for {style}. Looking for travelers to share the road, the costs and good moments.',
      'A {n}-day trip from {origin} to {destination}, with a taste for {style}. Looking for travelers to share the road, the costs and good moments.',
      {
        'origin': _shortPlace(_origin),
        'destination': _shortPlace(_destination),
        'style': tr(_travelStyle).toLowerCase(),
      },
    );
  }

  void _fillSuggestions() {
    if (!_titleEdited) {
      _titleController.text = _suggestedTitle;
    }
    if (!_summaryEdited) {
      _summaryController.text = _suggestedSummary;
    }
  }

  // Flow

  bool get _canContinue => switch (_step) {
    0 =>
      _origin.length >= 2 &&
          _destination.length >= 2 &&
          _viaStops.every((stop) => stop.label.length >= 2),
    3 => _perPerson > 0,
    4 =>
      _titleController.text.trim().length >= 4 &&
          _summaryController.text.trim().length >= 20,
    _ => true,
  };

  Future<void> _goTo(int step) async {
    FocusScope.of(context).unfocus();
    if (step == _stepCount - 1) {
      _fillSuggestions();
    }
    setState(() => _step = step);
    await _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  void _next() {
    if (_canContinue) {
      unawaited(HapticFeedback.lightImpact());
      unawaited(_goTo(_step + 1));
    }
  }

  void _back() {
    if (_step > 0) {
      unawaited(_goTo(_step - 1));
    }
  }

  TripDraft get _draft => TripDraft(
    title: _titleController.text.trim(),
    originCity: _origin,
    originCoordinate: _pickedOrigin?.label == _origin
        ? _pickedOrigin!.coordinate
        : null,
    startDate: _dates.start,
    endDate: _dates.end,
    stops: _stops,
    capacity: _capacity,
    lodgingTotal: _lodgingPerPerson * _capacity,
    transportTotal: _transportPerPerson * _capacity,
    currency: _currency,
    travelStyle: _travelStyle,
    summary: _summaryController.text.trim(),
  );

  /// What the trip card will look like once published.
  Trip get _previewTrip {
    final profile = ref.read(appAuthStateProvider).profile;
    final draft = _draft;
    return Trip(
      id: 'preview',
      hostId: profile?.id ?? '',
      hostName: profile?.displayName ?? '',
      hostHomeCity: profile?.homeCity,
      hostVerified: profile?.isLinkedInVerified ?? false,
      title: draft.title.isEmpty ? _suggestedTitle : draft.title,
      originCity: draft.originCity,
      startDate: draft.startDate,
      endDate: draft.endDate,
      stops: draft.stops,
      capacity: draft.capacity,
      confirmedTravelerCount: 0,
      lodgingTotal: draft.lodgingTotal,
      transportTotal: draft.transportTotal,
      currency: draft.currency,
      travelStyle: draft.travelStyle,
      summary: draft.summary,
      photos: [
        for (var index = 0; index < _photos.length; index++)
          TripPhoto(
            path: 'preview/$index',
            url: '',
            bytes: _photos[index].bytes,
          ),
      ],
    );
  }

  Future<void> _publish(TripCatalogController catalog) async {
    if (!_canContinue) {
      return;
    }
    try {
      var trip = await catalog.createTrip(_draft);
      if (_photos.isNotEmpty) {
        try {
          trip = await catalog.saveTripPhotos(
            trip,
            kept: const [],
            added: List.of(_photos),
          );
        } on Object {
          _showMessage(
            tr(
              'The trip was saved, but its photos could not be uploaded. Try again from Edit trip.',
            ),
          );
        }
      }
      unawaited(HapticFeedback.heavyImpact());
      if (mounted) {
        setState(() => _published = trip);
      }
    } on Object {
      _showMessage(
        catalog.errorMessage ?? tr('Trip could not be published. Try again.'),
      );
    }
  }

  Future<void> _pickPhotos() async {
    final remaining = Trip.maxPhotos - _photos.length;
    if (remaining <= 0) {
      return;
    }
    const maxSide = 1600.0;
    const quality = 82;
    // The multi-picker refuses a limit below 2.
    final picked = remaining == 1
        ? [
            ?await _imagePicker.pickImage(
              source: ImageSource.gallery,
              maxWidth: maxSide,
              maxHeight: maxSide,
              imageQuality: quality,
              requestFullMetadata: false,
            ),
          ]
        : await _imagePicker.pickMultiImage(
            maxWidth: maxSide,
            maxHeight: maxSide,
            imageQuality: quality,
            limit: remaining,
            requestFullMetadata: false,
          );
    final photos = <NewTripPhoto>[];
    for (final image in picked.take(remaining)) {
      photos.add(
        NewTripPhoto(
          bytes: await image.readAsBytes(),
          extension: image.name.split('.').last.toLowerCase(),
        ),
      );
    }
    if (mounted && photos.isNotEmpty) {
      setState(() => _photos.addAll(photos));
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);
    final published = _published;
    if (published != null) {
      return _PublishedView(trip: published);
    }

    return ListenableBuilder(
      listenable: catalog,
      builder: (context, child) {
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
                  ? const CloseButton()
                  : IconButton(
                      tooltip: tr('Back'),
                      onPressed: _back,
                      icon: const Icon(Icons.arrow_back_rounded),
                    ),
              title: FlowProgressBar(step: _step, count: _stepCount),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _routeStep(),
                        _datesStep(),
                        _groupStep(),
                        _budgetStep(),
                        _previewStep(),
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
                    child: FilledButton(
                      key: ValueKey(isLastStep ? 'publish-trip' : 'plan-next'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                      ),
                      onPressed: !_canContinue || catalog.isPublishing
                          ? null
                          : isLastStep
                          ? () => _publish(catalog)
                          : _next,
                      child: Text(
                        isLastStep
                            ? (catalog.isPublishing
                                  ? tr('Saving…')
                                  : tr('Publish trip'))
                            : tr('Continue'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _routeStep() {
    return FlowStep(
      title: tr('Where are you going?'),
      subtitle: tr('Pick a place or search for one.'),
      children: [
        PlaceField(
          fieldKey: const ValueKey('trip-destination'),
          controller: _destinationController,
          label: tr('Going to'),
          icon: Icons.flag_outlined,
          validator: (_) => null,
          onPicked: (place) => _pickedDestination = place,
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final place in PlanTripScreen.popularDestinations)
              ChoicePill(
                label: place,
                selected: _destination == place,
                onTap: () => _chooseDestination(place),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        PlaceField(
          fieldKey: const ValueKey('trip-origin'),
          controller: _originController,
          label: tr('Leaving from'),
          icon: Icons.trip_origin_rounded,
          validator: (_) => null,
          onPicked: (place) => _pickedOrigin = place,
        ),
        for (var index = 0; index < _viaStops.length; index++) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Expanded(
                child: PlaceField(
                  key: ObjectKey(_viaStops[index]),
                  fieldKey: ValueKey('trip-via-$index'),
                  controller: _viaStops[index].controller,
                  label: tr('Stop on the way'),
                  icon: Icons.more_vert_rounded,
                  validator: (_) => null,
                  onPicked: (place) => _viaStops[index].picked = place,
                ),
              ),
              IconButton(
                tooltip: tr('Remove stop'),
                onPressed: () => _removeViaStop(index),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
        ],
        if (_viaStops.length < _maxStops - 1)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('trip-add-via'),
              onPressed: _addViaStop,
              icon: const Icon(Icons.add_location_alt_outlined),
              label: Text(tr('Add a stop on the way')),
            ),
          ),
      ],
    );
  }

  Widget _datesStep() {
    final presets = [
      (_DatePreset.nextWeekend, tr('Next weekend')),
      (_DatePreset.weekendAfter, tr('The weekend after')),
      (_DatePreset.longWeekend, tr('Long weekend')),
    ];
    return FlowStep(
      title: tr('When?'),
      subtitle: tr('Pick a weekend or choose your own dates.'),
      children: [
        _BigValueCard(
          icon: Icons.date_range_rounded,
          value: formatTripDateRange(_dates.start, _dates.end),
          caption: trPlural(_days, '{n} day', '{n} days'),
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (preset, label) in presets)
              ChoicePill(
                label: label,
                selected: _datePreset == preset,
                onTap: () => _choosePreset(preset),
              ),
            ChoicePill(
              key: const ValueKey('trip-pick-dates'),
              label: tr('Choose dates'),
              icon: Icons.edit_calendar_outlined,
              selected: _datePreset == _DatePreset.custom,
              onTap: _pickDates,
            ),
          ],
        ),
      ],
    );
  }

  Widget _groupStep() {
    return FlowStep(
      title: tr('How many people in total?'),
      subtitle: tr('Including you. Costs are shared across the whole group.'),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton.filledTonal(
              key: const ValueKey('trip-capacity-less'),
              iconSize: 32,
              tooltip: tr('Fewer people'),
              onPressed: _capacity <= _minCapacity
                  ? null
                  : () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() => _capacity--);
                    },
              icon: const Icon(Icons.remove_rounded),
            ),
            SizedBox(
              width: 120,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Text(
                  '$_capacity',
                  key: ValueKey(_capacity),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: AppColors.green,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              key: const ValueKey('trip-capacity-more'),
              iconSize: 32,
              tooltip: tr('More people'),
              onPressed: _capacity >= _maxCapacity
                  ? null
                  : () {
                      unawaited(HapticFeedback.selectionClick());
                      setState(() => _capacity++);
                    },
              icon: const Icon(Icons.add_rounded),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.xxs,
          runSpacing: AppSpacing.xxs,
          children: [
            for (var seat = 0; seat < _capacity; seat++)
              Icon(
                seat == 0 ? Icons.person_rounded : Icons.person_outline_rounded,
                size: 32,
                color: seat == 0 ? AppColors.green : AppColors.muted,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          trPlural(_capacity - 1, 'You + {n} traveler', 'You + {n} travelers'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }

  Widget _budgetStep() {
    return FlowStep(
      title: tr('What will it cost each person?'),
      subtitle: tr('A rough estimate is fine. You can change it later.'),
      children: [
        _BigValueCard(
          icon: Icons.payments_outlined,
          value: formatTripMoney(_perPerson, _currency),
          caption: tr('per person, group total {total}', {
            'total': formatTripMoney(_perPerson * _capacity, _currency),
          }),
        ),
        const SizedBox(height: AppSpacing.lg),
        _AmountSlider(
          key: const ValueKey('trip-lodging-slider'),
          icon: Icons.bed_outlined,
          label: tr('Lodging'),
          value: _lodgingPerPerson,
          currency: _currency,
          onChanged: (value) => setState(() => _lodgingPerPerson = value),
        ),
        const SizedBox(height: AppSpacing.md),
        _AmountSlider(
          key: const ValueKey('trip-transport-slider'),
          icon: Icons.directions_car_outlined,
          label: tr('Transport'),
          value: _transportPerPerson,
          currency: _currency,
          onChanged: (value) => setState(() => _transportPerPerson = value),
        ),
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: SegmentedButton<String>(
            segments: [
              for (final currency in PlanTripScreen.currencies)
                ButtonSegment(value: currency, label: Text(currency)),
            ],
            selected: {_currency},
            onSelectionChanged: (selection) {
              unawaited(HapticFeedback.selectionClick());
              setState(() => _currency = selection.single);
            },
          ),
        ),
      ],
    );
  }

  Widget _previewStep() {
    return FlowStep(
      title: tr('Looking good!'),
      subtitle: tr('This is how travelers will see your trip.'),
      children: [
        IgnorePointer(
          child: TripCard(trip: _previewTrip, onTap: () {}),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(tr('Vibe'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final style in PlanTripScreen.travelStyles)
              ChoicePill(
                label: tr(style),
                selected: _travelStyle == style,
                onTap: () {
                  unawaited(HapticFeedback.selectionClick());
                  setState(() {
                    _travelStyle = style;
                    _fillSuggestions();
                  });
                },
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        TripPhotosEditor(
          kept: const [],
          added: _photos,
          onAdd: _pickPhotos,
          onRemoveKept: (_) {},
          onRemoveAdded: (index) => setState(() => _photos.removeAt(index)),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          key: const ValueKey('trip-title'),
          controller: _titleController,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: tr('Trip title'),
            suffixIcon: const Icon(Icons.edit_outlined),
          ),
          onChanged: (_) => setState(() => _titleEdited = true),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextField(
          key: const ValueKey('trip-summary'),
          controller: _summaryController,
          minLines: 3,
          maxLines: 6,
          maxLength: 600,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            labelText: tr('What should travelers expect?'),
            suffixIcon: const Icon(Icons.edit_outlined),
          ),
          onChanged: (_) => setState(() => _summaryEdited = true),
        ),
        Text(
          tr('Add stop plans, transport and timings later from Edit trip.'),
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
        ),
      ],
    );
  }
}

class _ViaStop {
  final controller = TextEditingController();
  PlaceSuggestion? picked;

  String get label => controller.text.trim();

  void dispose() => controller.dispose();
}

class _BigValueCard extends StatelessWidget {
  const _BigValueCard({
    required this.icon,
    required this.value,
    required this.caption,
  });

  final IconData icon;
  final String value;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 32, color: AppColors.green),
          const SizedBox(height: AppSpacing.xs),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              value,
              key: ValueKey(value),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.green,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
    );
  }
}

class _AmountSlider extends StatelessWidget {
  const _AmountSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.currency,
    required this.onChanged,
    super.key,
  });

  static const _max = 3000.0;
  static const _step = 50.0;

  final IconData icon;
  final String label;
  final double value;
  final String currency;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: AppColors.green),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.titleSmall),
            ),
            Text(
              formatTripMoney(value, currency),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        Slider(
          value: min(value, _max),
          max: _max,
          divisions: _max ~/ _step,
          label: formatTripMoney(value, currency),
          onChanged: (next) {
            if (next != value) {
              unawaited(HapticFeedback.selectionClick());
              onChanged(next);
            }
          },
        ),
      ],
    );
  }
}

class _PublishedView extends StatelessWidget {
  const _PublishedView({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.4, end: 1),
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.elasticOut,
                  builder: (context, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: const CircleAvatar(
                    radius: 48,
                    backgroundColor: AppColors.green,
                    child: Icon(
                      Icons.celebration_rounded,
                      size: 48,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                tr('Your trip is live!'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                tr(
                  'Travelers can now find it and ask to join. We will let you know when someone does.',
                ),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
              ),
              const Spacer(),
              FilledButton(
                key: const ValueKey('published-view-trip'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
                onPressed: () {
                  final router = GoRouter.of(context);
                  router.go(AppRoutes.trips);
                  unawaited(router.push(AppRoutes.tripDetails(trip.id)));
                },
                child: Text(tr('See my trip')),
              ),
              TextButton(
                key: const ValueKey('published-done'),
                onPressed: () => context.go(AppRoutes.trips),
                child: Text(tr('Back to my trips')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
