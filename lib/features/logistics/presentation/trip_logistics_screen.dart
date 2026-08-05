import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers/app_providers.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../join_requests/domain/trip_join_request.dart';
import '../../trips/domain/trip.dart';
import '../../trips/presentation/trip_formatters.dart';
import '../domain/trip_logistics.dart';

class TripLogisticsScreen extends ConsumerStatefulWidget {
  const TripLogisticsScreen({required this.tripId, super.key});

  final String tripId;

  @override
  ConsumerState<TripLogisticsScreen> createState() =>
      _TripLogisticsScreenState();
}

class _TripLogisticsScreenState extends ConsumerState<TripLogisticsScreen> {
  late Future<_LogisticsScreenData?> _data;
  int? _scenarioTravelers;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  Future<_LogisticsScreenData?> _load() async {
    final trip = await ref.read(tripCatalogProvider).findTrip(widget.tripId);
    if (trip == null) {
      return null;
    }
    final userId = ref.read(appAuthStateProvider).profile?.id;
    final requests = ref.read(joinRequestControllerProvider);
    if (trip.hostId != userId && requests.isLoading) {
      await requests.load();
    }
    final request = requests.requestForTrip(trip.id);
    final hasAccess =
        trip.hostId == userId || request?.status == JoinRequestStatus.confirmed;
    if (!hasAccess) {
      return _LogisticsScreenData(trip: trip, hasAccess: false);
    }
    final plan = await ref.read(logisticsControllerProvider).load(trip.id);
    return _LogisticsScreenData(trip: trip, plan: plan, hasAccess: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shared logistics')),
      body: FutureBuilder<_LogisticsScreenData?>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data;
          if (data == null) {
            return _Unavailable(
              message: 'This trip is no longer available.',
              onRetry: _retry,
            );
          }
          if (!data.hasAccess) {
            return const _AccessDenied();
          }
          if (snapshot.hasError || data.plan == null) {
            return _Unavailable(
              message: 'Logistics could not be loaded.',
              onRetry: _retry,
            );
          }

          final catalog = ref.watch(tripCatalogProvider);
          final logistics = ref.watch(logisticsControllerProvider);
          return ListenableBuilder(
            listenable: Listenable.merge([catalog, logistics]),
            builder: (context, child) {
              final trip = catalog.tripById(widget.tripId) ?? data.trip;
              final plan = logistics.planForTrip(widget.tripId) ?? data.plan!;
              return _buildContent(context, trip, plan);
            },
          );
        },
      ),
    );
  }

  Widget _buildContent(BuildContext context, Trip trip, TripLogistics plan) {
    final actualTravelers = trip.participantCount;
    final scenarioTravelers = (_scenarioTravelers ?? actualTravelers).clamp(
      1,
      trip.capacity,
    );
    final estimate = SharedCostEstimate.forTrip(trip, scenarioTravelers);
    final userId = ref.watch(appAuthStateProvider).profile?.id;
    final isHost = trip.hostId == userId;

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        80,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${trip.originCity} to ${trip.destinationCity}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.copyWith(color: AppColors.muted),
                  ),
                ],
              ),
            ),
            if (isHost)
              IconButton.filledTonal(
                key: const ValueKey('edit-logistics'),
                tooltip: 'Edit logistics',
                onPressed: () => _editLogistics(trip, plan),
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        _ActualGroupCard(trip: trip),
        const SizedBox(height: AppSpacing.xl),
        Text('Try a group size', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'See how the shared total changes from one person to the trip capacity.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        _ScenarioCalculator(
          trip: trip,
          travelerCount: scenarioTravelers,
          estimate: estimate,
          onChanged: (value) {
            setState(() => _scenarioTravelers = value);
          },
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Booking links', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Open the host’s shortlist in the provider app or website.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.md),
        if (!plan.hasBookingLinks)
          const _NoBookingLinks()
        else ...[
          if (plan.accommodationUrl != null)
            _BookingLinkCard(
              key: const ValueKey('accommodation-booking-link'),
              icon: Icons.bed_outlined,
              category: 'Accommodation',
              name: plan.accommodationName ?? 'Open accommodation option',
              uri: plan.accommodationUrl!,
              onOpen: _openExternal,
            ),
          if (plan.accommodationUrl != null && plan.transportUrl != null)
            const SizedBox(height: AppSpacing.sm),
          if (plan.transportUrl != null)
            _BookingLinkCard(
              key: const ValueKey('transport-booking-link'),
              icon: Icons.directions_car_outlined,
              category: 'Transport',
              name: plan.transportName ?? 'Open transport option',
              uri: plan.transportUrl!,
              onOpen: _openExternal,
            ),
        ],
        if (plan.notes != null) ...[
          const SizedBox(height: AppSpacing.md),
          _PlanningNote(note: plan.notes!),
        ],
        const SizedBox(height: AppSpacing.lg),
        const _ExternalBookingNotice(),
      ],
    );
  }

  void _retry() {
    setState(() => _data = _load());
  }

  Future<void> _openExternal(Uri uri) async {
    try {
      final opened = await ref.read(externalLinkLauncherProvider).open(uri);
      if (!opened && mounted) {
        _showMessage('This booking link could not be opened.');
      }
    } on Object {
      if (mounted) {
        _showMessage('This booking link could not be opened.');
      }
    }
  }

  Future<void> _editLogistics(Trip trip, TripLogistics plan) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _LogisticsEditor(trip: trip, plan: plan),
    );
    if (saved == true && mounted) {
      _scenarioTravelers = null;
      _showMessage('Shared logistics updated.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _LogisticsScreenData {
  const _LogisticsScreenData({
    required this.trip,
    required this.hasAccess,
    this.plan,
  });

  final Trip trip;
  final bool hasAccess;
  final TripLogistics? plan;
}

class _ActualGroupCard extends StatelessWidget {
  const _ActualGroupCard({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final estimate = SharedCostEstimate.forTrip(trip, trip.participantCount);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.green,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: Colors.white24,
            foregroundColor: Colors.white,
            child: Icon(Icons.group_outlined),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${trip.participantCount} confirmed in the group',
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                Text(
                  '${formatTripMoney(estimate.totalPerPerson, trip.currency)} each today · ${trip.openSeats} open ${trip.openSeats == 1 ? 'seat' : 'seats'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScenarioCalculator extends StatelessWidget {
  const _ScenarioCalculator({
    required this.trip,
    required this.travelerCount,
    required this.estimate,
    required this.onChanged,
  });

  final Trip trip;
  final int travelerCount;
  final SharedCostEstimate estimate;
  final ValueChanged<int> onChanged;

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
          Row(
            children: [
              Text(
                'Group size',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.greenSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$travelerCount ${travelerCount == 1 ? 'person' : 'people'}',
                  key: const ValueKey('scenario-group-size'),
                  style: const TextStyle(
                    color: AppColors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Slider(
            key: const ValueKey('group-size-slider'),
            min: 1,
            max: trip.capacity.toDouble(),
            divisions: trip.capacity - 1,
            value: travelerCount.toDouble(),
            label: '$travelerCount',
            onChanged: (value) => onChanged(value.round()),
          ),
          Row(
            children: [
              const Text('1'),
              const Spacer(),
              Text('${trip.capacity} max'),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: Divider(),
          ),
          _EstimateLine(
            label: 'Lodging per person',
            value: formatTripMoney(estimate.lodgingPerPerson, trip.currency),
          ),
          const SizedBox(height: AppSpacing.sm),
          _EstimateLine(
            label: 'Transport per person',
            value: formatTripMoney(estimate.transportPerPerson, trip.currency),
          ),
          const SizedBox(height: AppSpacing.md),
          _EstimateLine(
            label: 'Estimated total each',
            value: formatTripMoney(estimate.totalPerPerson, trip.currency),
            emphasized: true,
          ),
        ],
      ),
    );
  }
}

class _EstimateLine extends StatelessWidget {
  const _EstimateLine({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final style = emphasized
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _BookingLinkCard extends StatelessWidget {
  const _BookingLinkCard({
    required this.icon,
    required this.category,
    required this.name,
    required this.uri,
    required this.onOpen,
    super.key,
  });

  final IconData icon;
  final String category;
  final String name;
  final Uri uri;
  final ValueChanged<Uri> onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.terracottaSoft,
            foregroundColor: AppColors.terracotta,
            child: Icon(icon),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
                Text(name, style: Theme.of(context).textTheme.titleMedium),
                Text(
                  uri.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Open externally',
            onPressed: () => onOpen(uri),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
    );
  }
}

class _NoBookingLinks extends StatelessWidget {
  const _NoBookingLinks();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
      ),
      child: const Row(
        children: [
          Icon(Icons.link_off_rounded, color: AppColors.muted),
          SizedBox(width: AppSpacing.sm),
          Expanded(child: Text('The host has not shared a shortlist yet.')),
        ],
      ),
    );
  }
}

class _PlanningNote extends StatelessWidget {
  const _PlanningNote({required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.greenSoft,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.sticky_note_2_outlined, color: AppColors.green),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(note)),
        ],
      ),
    );
  }
}

class _ExternalBookingNotice extends StatelessWidget {
  const _ExternalBookingNotice();

  @override
  Widget build(BuildContext context) {
    return Text(
      'CoTravel coordinates the group and estimates shared costs. Booking and payment happen directly with the third-party provider.',
      textAlign: TextAlign.center,
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
    );
  }
}

class _LogisticsEditor extends ConsumerStatefulWidget {
  const _LogisticsEditor({required this.trip, required this.plan});

  final Trip trip;
  final TripLogistics plan;

  @override
  ConsumerState<_LogisticsEditor> createState() => _LogisticsEditorState();
}

class _LogisticsEditorState extends ConsumerState<_LogisticsEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lodging;
  late final TextEditingController _transport;
  late final TextEditingController _accommodationName;
  late final TextEditingController _accommodationUrl;
  late final TextEditingController _transportName;
  late final TextEditingController _transportUrl;
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _lodging = TextEditingController(text: _number(widget.trip.lodgingTotal));
    _transport = TextEditingController(
      text: _number(widget.trip.transportTotal),
    );
    _accommodationName = TextEditingController(
      text: widget.plan.accommodationName,
    );
    _accommodationUrl = TextEditingController(
      text: widget.plan.accommodationUrl?.toString(),
    );
    _transportName = TextEditingController(text: widget.plan.transportName);
    _transportUrl = TextEditingController(
      text: widget.plan.transportUrl?.toString(),
    );
    _notes = TextEditingController(text: widget.plan.notes);
  }

  @override
  void dispose() {
    _lodging.dispose();
    _transport.dispose();
    _accommodationName.dispose();
    _accommodationUrl.dispose();
    _transportName.dispose();
    _transportUrl.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(logisticsControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) {
        final saving = controller.isSaving(widget.trip.id);
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.lg,
              bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Update shared logistics',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Use total group costs. The app calculates each person’s share.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('logistics-lodging-total'),
                            controller: _lodging,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Lodging total',
                              suffixText: widget.trip.currency,
                            ),
                            validator: _costValidator,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            key: const ValueKey('logistics-transport-total'),
                            controller: _transport,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: 'Transport total',
                              suffixText: widget.trip.currency,
                            ),
                            validator: _costValidator,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _accommodationName,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Accommodation label',
                        hintText: 'Guesthouse shortlist',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('accommodation-booking-url'),
                      controller: _accommodationUrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Accommodation link',
                        hintText: 'https://…',
                      ),
                      validator: _urlValidator,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _transportName,
                      maxLength: 100,
                      decoration: const InputDecoration(
                        labelText: 'Transport label',
                        hintText: 'Transfer option',
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      key: const ValueKey('transport-booking-url'),
                      controller: _transportUrl,
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'Transport link',
                        hintText: 'https://…',
                      ),
                      validator: _urlValidator,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _notes,
                      maxLength: 600,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        labelText: 'Planning note',
                        alignLabelWithHint: true,
                      ),
                    ),
                    if (controller.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        controller.errorMessage!,
                        style: const TextStyle(color: AppColors.error),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      key: const ValueKey('save-logistics'),
                      onPressed: saving ? null : _save,
                      child: Text(saving ? 'Saving…' : 'Save logistics'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String? _costValidator(String? value) {
    final amount = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (amount == null || amount < 0) {
      return 'Enter a valid amount';
    }
    return null;
  }

  String? _urlValidator(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(raw);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      return 'Use a full http or https link';
    }
    if (raw.length > 500) {
      return 'Keep the link under 500 characters';
    }
    return null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final lodging = _parseAmount(_lodging.text);
    final transport = _parseAmount(_transport.text);
    if (lodging + transport <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a lodging or transport estimate.')),
      );
      return;
    }

    try {
      await ref
          .read(logisticsControllerProvider)
          .save(
            trip: widget.trip,
            draft: LogisticsDraft(
              lodgingTotal: lodging,
              transportTotal: transport,
              accommodationName: _optional(_accommodationName.text),
              accommodationUrl: _uri(_accommodationUrl.text),
              transportName: _optional(_transportName.text),
              transportUrl: _uri(_transportUrl.text),
              notes: _optional(_notes.text),
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on Object {
      // The controller exposes the readable error inside this form.
    }
  }

  double _parseAmount(String value) {
    return double.parse(value.trim().replaceAll(',', '.'));
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  Uri? _uri(String value) {
    final raw = _optional(value);
    return raw == null ? null : Uri.parse(raw);
  }

  String _number(double value) {
    return value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(2);
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return const _CenteredMessage(
      icon: Icons.lock_outline_rounded,
      title: 'Available after confirmation',
      message:
          'Booking links and group logistics are private to the host and confirmed travelers.',
    );
  }
}

class _Unavailable extends StatelessWidget {
  const _Unavailable({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredMessage(
      icon: Icons.route_outlined,
      title: 'Logistics unavailable',
      message: message,
      action: TextButton(onPressed: onRetry, child: const Text('Try again')),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: AppColors.green),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(message, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
