import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../core/analytics/product_analytics.dart';
import '../domain/trip.dart';
import 'trip_formatters.dart';

class CreateTripScreen extends ConsumerStatefulWidget {
  const CreateTripScreen({super.key});

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

  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _originController = TextEditingController();
  final _lodgingController = TextEditingController();
  final _transportController = TextEditingController();
  final _summaryController = TextEditingController();
  final _stops = <_StopFields>[];

  late DateTimeRange _dateRange;
  String _travelStyle = _travelStyles.first;
  String _currency = _currencies.first;
  int _capacity = 4;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(productAnalyticsProvider).track(ProductEvent.tripBuilderOpened),
    );
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
        _showMessage('Route dates must follow the order of your stops.');
        return;
      }
    }

    final lodging = double.tryParse(_lodgingController.text.trim()) ?? 0;
    final transport = double.tryParse(_transportController.text.trim()) ?? 0;
    if (lodging + transport <= 0) {
      _showMessage('Add a lodging or transport estimate.');
      return;
    }

    final catalog = ref.read(tripCatalogProvider);
    try {
      await catalog.createTrip(
        TripDraft(
          title: _titleController.text.trim(),
          originCity: _originController.text.trim(),
          startDate: _dateRange.start,
          endDate: _dateRange.end,
          stops: _stops
              .map(
                (stop) => TripStop(
                  city: stop.cityController.text.trim(),
                  arrivalDate: stop.arrivalDate,
                  notes: _optional(stop.notesController.text),
                ),
              )
              .toList(),
          capacity: _capacity,
          lodgingTotal: lodging,
          transportTotal: transport,
          currency: _currency,
          travelStyle: _travelStyle,
          summary: _summaryController.text.trim(),
        ),
      );
      if (mounted) {
        context.go(AppRoutes.trips);
      }
    } on Object {
      if (mounted) {
        _showMessage(
          catalog.errorMessage ?? 'Trip could not be published. Try again.',
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

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(tripCatalogProvider);

    return ListenableBuilder(
      listenable: catalog,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(title: const Text('Plan a trip')),
          body: SafeArea(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.sm,
                  AppSpacing.lg,
                  96,
                ),
                children: [
                  Text(
                    'A clear plan attracts the right people.',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Share enough detail to make the route, pace, and expected costs easy to understand.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(number: '01', title: 'The idea'),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('trip-title'),
                    controller: _titleController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLength: 80,
                    decoration: const InputDecoration(
                      labelText: 'Trip title',
                      hintText: 'Atlas villages weekend',
                    ),
                    validator: (value) {
                      final length = value?.trim().length ?? 0;
                      return length < 4 ? 'Use at least 4 characters' : null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextFormField(
                    key: const ValueKey('trip-origin'),
                    controller: _originController,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Leaving from',
                      prefixIcon: Icon(Icons.trip_origin_rounded),
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 2
                        ? 'Add a departure city'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  OutlinedButton.icon(
                    key: const ValueKey('trip-date-range'),
                    onPressed: _chooseTripDates,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text(
                      formatTripDateRange(_dateRange.start, _dateRange.end),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  _SectionLabel(
                    number: '02',
                    title: 'The route',
                    trailing: '${_stops.length}/8 stops',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  for (var index = 0; index < _stops.length; index++) ...[
                    _StopEditor(
                      key: ValueKey('trip-stop-$index'),
                      index: index,
                      fields: _stops[index],
                      canRemove: _stops.length > 1,
                      onChooseDate: () => _chooseStopDate(index),
                      onRemove: () => _removeStop(index),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  OutlinedButton.icon(
                    onPressed: _stops.length == 8 ? null : _addStop,
                    icon: const Icon(Icons.add_location_alt_outlined),
                    label: const Text('Add another stop'),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _SectionLabel(number: '03', title: 'Group and budget'),
                  const SizedBox(height: AppSpacing.md),
                  DropdownButtonFormField<int>(
                    key: const ValueKey('trip-capacity'),
                    initialValue: _capacity,
                    decoration: const InputDecoration(
                      labelText: 'Total group size',
                      prefixIcon: Icon(Icons.group_outlined),
                    ),
                    items: [
                      for (var count = 2; count <= 12; count++)
                        DropdownMenuItem(
                          value: count,
                          child: Text('$count people'),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _capacity = value);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('trip-lodging'),
                          controller: _lodgingController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Lodging total',
                          ),
                          validator: _validateCost,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextFormField(
                          key: const ValueKey('trip-transport'),
                          controller: _transportController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d*\.?\d{0,2}'),
                            ),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Transport total',
                          ),
                          validator: _validateCost,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  DropdownButtonFormField<String>(
                    initialValue: _currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: _currencies
                        .map(
                          (currency) => DropdownMenuItem(
                            value: currency,
                            child: Text(currency),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _currency = value);
                      }
                    },
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _CostPreview(
                    capacity: _capacity,
                    estimatedShare: _estimatedShare,
                    currency: _currency,
                  ),
                  const SizedBox(height: AppSpacing.xl),
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
                            selected: _travelStyle == style,
                            onSelected: (_) {
                              setState(() => _travelStyle = style);
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextFormField(
                    key: const ValueKey('trip-summary'),
                    controller: _summaryController,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 600,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'What should travelers expect?',
                      hintText:
                          'Describe the pace, activities, and the kind of group you hope to form.',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 20
                        ? 'Write at least 20 characters'
                        : null,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  FilledButton.icon(
                    key: const ValueKey('publish-trip'),
                    onPressed: catalog.isPublishing ? null : _publish,
                    icon: catalog.isPublishing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.public_rounded),
                    label: Text(
                      catalog.isPublishing ? 'Publishing…' : 'Publish trip',
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

  String? _validateCost(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    return amount == null || amount < 0 ? 'Use a valid amount' : null;
  }
}

class _StopFields {
  _StopFields({required this.arrivalDate});

  final cityController = TextEditingController();
  final notesController = TextEditingController();
  DateTime arrivalDate;

  void dispose() {
    cityController.dispose();
    notesController.dispose();
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({
    required this.number,
    required this.title,
    this.trailing,
  });

  final String number;
  final String title;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: AppColors.greenSoft,
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.green,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (trailing != null)
          Text(
            trailing!,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
      ],
    );
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
                  index == 0 ? 'First stop' : 'Stop ${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              if (canRemove)
                IconButton(
                  onPressed: onRemove,
                  tooltip: 'Remove stop',
                  icon: const Icon(Icons.close_rounded),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          TextFormField(
            key: ValueKey('trip-stop-city-$index'),
            controller: fields.cityController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'City or place',
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
            validator: (value) =>
                (value?.trim().length ?? 0) < 2 ? 'Add a destination' : null,
          ),
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            key: ValueKey('trip-stop-date-$index'),
            onPressed: onChooseDate,
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text('Arrive ${formatTripDate(fields.arrivalDate)}'),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            controller: fields.notesController,
            maxLength: 240,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Plan for this stop (optional)',
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
                  'Estimated per person when all $capacity places are filled',
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
