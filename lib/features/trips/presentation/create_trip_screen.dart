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
import '../../../core/widgets/empty_state.dart';
import '../application/trip_catalog_controller.dart';
import '../data/place_search.dart';
import '../domain/trip.dart';
import 'trip_formatters.dart';
import 'widgets/place_field.dart';
import 'widgets/trip_photos_editor.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({this.tripId, super.key});

  // Edits this hosted trip when set; otherwise creates a new one.
  final String? tripId;

  @override
  ConsumerState<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends ConsumerState<CreateTripScreen> {
  static const _travelStyles = [
    'Culture',
    'Food',
    'Nature',
    'Road trips',
    'Budget',
    'Remote work',
  ];
  static const _currencies = ['MAD', 'EUR', 'USD'];

  int _step = 0;
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _originController = TextEditingController();
  PlaceSuggestion? _pickedOrigin;
  final _lodgingController = TextEditingController();
  final _transportController = TextEditingController();
  final _summaryController = TextEditingController();
  final _stops = <_StopFields>[];

  late DateTimeRange _dateRange;
  String _travelStyle = _travelStyles.first;
  String _currency = _currencies.first;
  int _capacity = 4;
  int _minimumCapacity = 2;
  Trip? _editedTrip;
  final _imagePicker = ImagePicker();
  final _keptPhotos = <TripPhoto>[];
  final _addedPhotos = <NewTripPhoto>[];

  bool get _isEditing => widget.tripId != null;

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final trip = ref.read(tripCatalogProvider).tripById(widget.tripId!);
      if (trip != null) {
        _loadTrip(trip);
        return;
      }
    } else {
      unawaited(
        ref
            .read(productAnalyticsProvider)
            .track(ProductEvent.tripBuilderOpened),
      );
    }
    final today = DateTime.now();
    final start = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 14));
    _dateRange = DateTimeRange(
      start: start,
      end: start.add(const Duration(days: 3)),
    );
    _stops.add(_StopFields(arrivalDate: _dateRange.end));
  }

  void _loadTrip(Trip trip) {
    _editedTrip = trip;
    _titleController.text = trip.title;
    _originController.text = trip.originCity;
    _lodgingController.text = trip.lodgingTotal.toStringAsFixed(2);
    _transportController.text = trip.transportTotal.toStringAsFixed(2);
    _summaryController.text = trip.summary;
    _dateRange = DateTimeRange(start: trip.startDate, end: trip.endDate);
    _travelStyle = trip.travelStyle;
    _currency = trip.currency;
    _capacity = trip.capacity;
    _minimumCapacity = max(2, trip.participantCount);
    _keptPhotos.addAll(trip.photos);
    for (final stop in trip.stops) {
      _stops.add(_StopFields.fromStop(stop));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _originController.dispose();
    _lodgingController.dispose();
    _transportController.dispose();
    _summaryController.dispose();
    for (final stop in _stops) {
      stop.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final remaining = Trip.maxPhotos - _keptPhotos.length - _addedPhotos.length;
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
      setState(() => _addedPhotos.addAll(photos));
    }
  }

  bool _photosChanged(Trip trip) {
    if (_addedPhotos.isNotEmpty || _keptPhotos.length != trip.photos.length) {
      return true;
    }
    for (var index = 0; index < _keptPhotos.length; index++) {
      if (_keptPhotos[index].path != trip.photos[index].path) {
        return true;
      }
    }
    return false;
  }

  /// Saved after the trip itself, so a failed upload never loses the trip.
  Future<void> _savePhotos(TripCatalogController catalog, Trip trip) async {
    if (!_photosChanged(trip)) {
      return;
    }
    try {
      await catalog.saveTripPhotos(
        trip,
        kept: List.of(_keptPhotos),
        added: List.of(_addedPhotos),
      );
    } on Object {
      if (mounted) {
        _showMessage(
          tr(
            'The trip was saved, but its photos could not be uploaded. Try again from Edit trip.',
          ),
        );
      }
    }
  }

  Future<void> _chooseTripDates() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _dateRange,
    );
    if (picked == null) {
      return;
    }

    setState(() {
      _dateRange = picked;
      for (final stop in _stops) {
        if (stop.arrivalDate.isBefore(picked.start) ||
            stop.arrivalDate.isAfter(picked.end)) {
          stop.arrivalDate = picked.end;
        }
      }
    });
  }

  Future<void> _chooseStopDate(int index) async {
    final stop = _stops[index];
    final picked = await showDatePicker(
      context: context,
      firstDate: _dateRange.start,
      lastDate: _dateRange.end,
      initialDate: stop.arrivalDate,
    );
    if (picked != null) {
      setState(() => stop.arrivalDate = picked);
    }
  }

  void _addStop() {
    if (_stops.length == 8) {
      return;
    }
    setState(() => _stops.add(_StopFields(arrivalDate: _dateRange.end)));
  }

  void _removeStop(int index) {
    if (_stops.length == 1) {
      return;
    }
    setState(() => _stops.removeAt(index).dispose());
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    for (var index = 1; index < _stops.length; index++) {
      if (_stops[index].arrivalDate.isBefore(_stops[index - 1].arrivalDate)) {
        _showMessage(tr('Route dates must follow the order of your stops.'));
        return;
      }
    }

    final lodging = double.tryParse(_lodgingController.text.trim()) ?? 0;
    final transport = double.tryParse(_transportController.text.trim()) ?? 0;
    if (lodging + transport <= 0) {
      _showMessage(tr('Add a lodging or transport estimate.'));
      return;
    }

    final catalog = ref.read(tripCatalogProvider);
    final draft = TripDraft(
      title: _titleController.text.trim(),
      originCity: _originController.text.trim(),
      originCoordinate: _pickedOrigin?.label == _originController.text.trim()
          ? _pickedOrigin!.coordinate
          : null,
      startDate: _dateRange.start,
      endDate: _dateRange.end,
      stops: _stops.map((stop) => stop.toStop(_optional)).toList(),
      capacity: _capacity,
      lodgingTotal: lodging,
      transportTotal: transport,
      currency: _currency,
      travelStyle: _travelStyle,
      summary: _summaryController.text.trim(),
    );
    try {
      if (_isEditing) {
        final trip = await catalog.updateTrip(widget.tripId!, draft);
        await _savePhotos(catalog, trip);
        if (mounted) {
          context.pop();
        }
      } else {
        final trip = await catalog.createTrip(draft);
        await _savePhotos(catalog, trip);
        if (mounted) {
          context.go(AppRoutes.trips);
        }
      }
    } on Object {
      if (mounted) {
        _showMessage(
          catalog.errorMessage ?? tr('Trip could not be published. Try again.'),
        );
      }
    }
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  double get _estimatedShare {
    final lodging = double.tryParse(_lodgingController.text.trim()) ?? 0;
    final transport = double.tryParse(_transportController.text.trim()) ?? 0;
    return (lodging + transport) / _capacity;
  }

  List<Widget> _routeFields() {
    return [
      TextFormField(
        key: const ValueKey('trip-title'),
        controller: _titleController,
        textCapitalization: TextCapitalization.sentences,
        maxLength: 80,
        decoration: InputDecoration(
          labelText: tr('Trip title'),
          hintText: tr('Atlas villages weekend'),
        ),
        validator: (value) {
          final length = value?.trim().length ?? 0;
          return length < 4 ? tr('Use at least 4 characters') : null;
        },
      ),
      SizedBox(height: AppSpacing.sm),
      PlaceField(
        fieldKey: const ValueKey('trip-origin'),
        controller: _originController,
        label: tr('Leaving from'),
        icon: Icons.trip_origin_rounded,
        mappedLabel: _editedTrip?.originCoordinate == null
            ? null
            : _editedTrip!.originCity,
        onPicked: (place) => _pickedOrigin = place,
        validator: (value) =>
            (value?.trim().length ?? 0) < 2 ? tr('Add a departure city') : null,
      ),
      SizedBox(height: AppSpacing.sm),
      OutlinedButton.icon(
        key: ValueKey('trip-date-range'),
        onPressed: _chooseTripDates,
        icon: Icon(Icons.date_range_outlined),
        label: Text(formatTripDateRange(_dateRange.start, _dateRange.end)),
      ),
      SizedBox(height: AppSpacing.lg),
      Row(
        children: [
          Expanded(
            child: Text(
              tr('Route'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Text(
            tr('{length}/8 stops', {'length': _stops.length}),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
        ],
      ),
      SizedBox(height: AppSpacing.sm),
      for (var index = 0; index < _stops.length; index++) ...[
        _StopEditor(
          key: ValueKey('trip-stop-$index'),
          index: index,
          fields: _stops[index],
          canRemove: _stops.length > 1,
          onChooseDate: () => _chooseStopDate(index),
          onRemove: () => _removeStop(index),
        ),
        SizedBox(height: AppSpacing.sm),
      ],
      OutlinedButton.icon(
        onPressed: _stops.length == 8 ? null : _addStop,
        icon: Icon(Icons.add_location_alt_outlined),
        label: Text(tr('Add another stop')),
      ),
      SizedBox(height: AppSpacing.lg),
      DropdownButtonFormField<int>(
        key: ValueKey('trip-capacity'),
        initialValue: _capacity,
        decoration: InputDecoration(
          labelText: tr('Total group size'),
          prefixIcon: Icon(Icons.group_outlined),
        ),
        items: [
          for (var count = _minimumCapacity; count <= 12; count++)
            DropdownMenuItem(
              value: count,
              child: Text(tr('{count} people', {'count': count})),
            ),
        ],
        onChanged: (value) {
          if (value != null) {
            setState(() => _capacity = value);
          }
        },
      ),
    ];
  }

  List<Widget> _budgetFields() {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextFormField(
              key: ValueKey('trip-lodging'),
              controller: _lodgingController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Lodging total')),
              validator: _validateCost,
            ),
          ),
          SizedBox(width: AppSpacing.sm),
          Expanded(
            child: TextFormField(
              key: ValueKey('trip-transport'),
              controller: _transportController,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(labelText: tr('Transport total')),
              validator: _validateCost,
            ),
          ),
        ],
      ),
      SizedBox(height: AppSpacing.sm),
      DropdownButtonFormField<String>(
        initialValue: _currency,
        decoration: InputDecoration(labelText: tr('Currency')),
        items: {..._currencies, _currency}
            .map(
              (currency) =>
                  DropdownMenuItem(value: currency, child: Text(currency)),
            )
            .toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() => _currency = value);
          }
        },
      ),
      SizedBox(height: AppSpacing.md),
      _CostPreview(
        capacity: _capacity,
        estimatedShare: _estimatedShare,
        currency: _currency,
      ),
    ];
  }

  List<Widget> _detailFields() {
    return [
      Text(tr('Travel style'), style: Theme.of(context).textTheme.titleMedium),
      SizedBox(height: AppSpacing.xs),
      Wrap(
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: {..._travelStyles, _travelStyle}
            .map(
              (style) => ChoiceChip(
                label: Text(tr(style)),
                selected: _travelStyle == style,
                onSelected: (_) {
                  setState(() => _travelStyle = style);
                },
              ),
            )
            .toList(),
      ),
      SizedBox(height: AppSpacing.lg),
      TextFormField(
        key: ValueKey('trip-summary'),
        controller: _summaryController,
        minLines: 4,
        maxLines: 7,
        maxLength: 600,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: tr('What should travelers expect?'),
          hintText: tr(
            'Describe the pace, activities, and the kind of group you hope to form.',
          ),
        ),
        validator: (value) => (value?.trim().length ?? 0) < 20
            ? tr('Write at least 20 characters')
            : null,
      ),
      SizedBox(height: AppSpacing.lg),
      TripPhotosEditor(
        kept: _keptPhotos,
        added: _addedPhotos,
        onAdd: _pickPhotos,
        onRemoveKept: (index) => setState(() => _keptPhotos.removeAt(index)),
        onRemoveAdded: (index) => setState(() => _addedPhotos.removeAt(index)),
      ),
    ];
  }

  Widget _publishButton(TripCatalogController catalog) {
    return FilledButton.icon(
      key: ValueKey('publish-trip'),
      onPressed: catalog.isPublishing ? null : _publish,
      icon: catalog.isPublishing
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.public_rounded),
      label: Text(
        catalog.isPublishing
            ? tr('Saving…')
            : _isEditing
            ? tr('Save changes')
            : tr('Publish trip'),
      ),
    );
  }

  static List<(String, String)> get _stepTitles => [
    (
      tr('Start with the route.'),
      tr('You can adjust costs and traveler preferences later.'),
    ),
    (
      tr('Estimate the budget.'),
      tr('Totals are split equally across the full group.'),
    ),
    (
      tr('Set the expectations.'),
      tr('Help the right travelers recognize this trip.'),
    ),
  ];

  void _continue() {
    if (_formKey.currentState!.validate()) {
      setState(() => _step++);
    }
  }

  void _back() => setState(() => _step--);

  Widget _bottomAction(TripCatalogController catalog) {
    final Widget action = _isEditing || _step == 2
        ? _publishButton(catalog)
        : FilledButton(
            key: const ValueKey('trip-continue'),
            onPressed: _continue,
            child: Text(
              _step == 0 ? tr('Continue to budget') : tr('Continue to details'),
            ),
          );
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: action,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);

    if (_isEditing && _editedTrip == null) {
      return Scaffold(
        appBar: AppBar(title: Text(tr('Edit trip'))),
        body: EmptyState(
          icon: Icons.search_off_rounded,
          title: tr('Trip not found'),
          message: tr('Only trips you host can be edited.'),
        ),
      );
    }

    return ListenableBuilder(
      listenable: catalog,
      builder: (context, child) {
        return PopScope(
          canPop: _isEditing || _step == 0,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              _back();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(_isEditing ? tr('Edit trip') : tr('Create a trip')),
              centerTitle: true,
              leading: !_isEditing && _step > 0
                  ? BackButton(onPressed: _back)
                  : null,
              actions: [
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.md),
                    child: Center(
                      child: Text(tr('{step} of 3', {'step': _step + 1})),
                    ),
                  ),
              ],
              bottom: _isEditing
                  ? null
                  : PreferredSize(
                      preferredSize: const Size.fromHeight(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        child: LinearProgressIndicator(
                          value: (_step + 1) / 3,
                          backgroundColor: AppColors.border,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
            ),
            bottomNavigationBar: _bottomAction(catalog),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: _isEditing
                    ? [
                        ..._routeFields(),
                        const SizedBox(height: AppSpacing.lg),
                        ..._budgetFields(),
                        const SizedBox(height: AppSpacing.lg),
                        ..._detailFields(),
                      ]
                    : [
                        Text(
                          _stepTitles[_step].$1,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          _stepTitles[_step].$2,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppColors.muted),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        ...switch (_step) {
                          0 => _routeFields(),
                          1 => _budgetFields(),
                          _ => _detailFields(),
                        },
                      ],
              ),
            ),
          ),
        );
      },
    );
  }

  String? _validateCost(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    return amount == null || amount < 0 ? tr('Use a valid amount') : null;
  }
}

class _StopFields {
  _StopFields({required this.arrivalDate});

  _StopFields.fromStop(TripStop stop)
    : arrivalDate = stop.arrivalDate,
      _source = stop {
    cityController.text = stop.city;
    notesController.text = stop.notes ?? '';
  }

  final cityController = TextEditingController();
  final notesController = TextEditingController();
  DateTime arrivalDate;
  TripStop? _source;

  /// The suggestion picked for this stop, which carries its coordinates.
  PlaceSuggestion? picked;

  /// The saved place name that already has coordinates.
  String? get mappedLabel => _source?.coordinate == null ? null : _source!.city;

  TripStop toStop(String? Function(String) optional) {
    final city = cityController.text.trim();
    final notes = optional(notesController.text);
    final source = _source;
    // Typing over a picked place drops its coordinates.
    final coordinate = picked?.label == city ? picked!.coordinate : null;
    // Route details the form does not show survive unless the place changes.
    return source == null || source.city != city
        ? TripStop(
            city: city,
            arrivalDate: arrivalDate,
            notes: notes,
            latitude: coordinate?.latitude,
            longitude: coordinate?.longitude,
          )
        : TripStop(
            city: city,
            arrivalDate: arrivalDate,
            notes: notes,
            latitude: source.latitude,
            longitude: source.longitude,
            type: source.type,
            travelMode: source.travelMode,
            travelDurationMinutes: source.travelDurationMinutes,
            isOptional: source.isOptional,
          );
  }

  void dispose() {
    cityController.dispose();
    notesController.dispose();
  }
}

class _StopEditor extends StatelessWidget {
  const _StopEditor({
    required this.index,
    required this.fields,
    required this.canRemove,
    required this.onChooseDate,
    required this.onRemove,
    super.key,
  });

  final int index;
  final _StopFields fields;
  final bool canRemove;
  final VoidCallback onChooseDate;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  index == 0
                      ? tr('First stop')
                      : tr('Stop {index}', {'index': index + 1}),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: tr('Remove stop'),
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          PlaceField(
            fieldKey: ValueKey('trip-stop-city-$index'),
            controller: fields.cityController,
            label: tr('City or place'),
            icon: Icons.location_on_outlined,
            mappedLabel: fields.mappedLabel,
            onPicked: (place) => fields.picked = place,
            validator: (value) => (value?.trim().length ?? 0) < 2
                ? tr('Add a destination')
                : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: ValueKey('trip-stop-date-$index'),
            onPressed: onChooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(
              tr('Arrive {date}', {'date': formatTripDate(fields.arrivalDate)}),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: fields.notesController,
            maxLength: 240,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr('Plan for this stop (optional)'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CostPreview extends StatelessWidget {
  const _CostPreview({
    required this.capacity,
    required this.estimatedShare,
    required this.currency,
  });

  final int capacity;
  final double estimatedShare;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.calculate_outlined, color: AppColors.green),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatTripMoney(estimatedShare, currency),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  tr(
                    'Estimated per person when all {capacity} places are filled',
                    {'capacity': capacity},
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
