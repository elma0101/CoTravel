import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/providers/app_providers.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../data/place_search.dart';
import '../../domain/trip_route.dart';

/// A place field that suggests real places as people type. Other names are
/// still accepted, and the field says when one will not appear on the map.
class PlaceField extends ConsumerStatefulWidget {
  const PlaceField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    this.onPicked,
    this.mappedLabel,
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FormFieldValidator<String> validator;

  /// Called with the suggestion someone picks, coordinates included.
  final ValueChanged<PlaceSuggestion>? onPicked;

  /// A label already saved with coordinates, such as a stop being edited.
  final String? mappedLabel;

  @override
  ConsumerState<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends ConsumerState<PlaceField> {
  static const _typingPause = Duration(milliseconds: 300);

  final _focusNode = FocusNode();
  String? _pickedLabel;
  String _latestQuery = '';
  Iterable<PlaceSuggestion> _lastOptions = const [];

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<Iterable<PlaceSuggestion>> _options(TextEditingValue value) async {
    final text = value.text.trim();
    _latestQuery = text;
    // Nothing to suggest once a suggestion fills the field.
    if (text.length < 2 || text == _pickedLabel) {
      return _lastOptions = const [];
    }
    // Only search once typing pauses, and drop answers to older text.
    await Future<void>.delayed(_typingPause);
    if (_latestQuery != text || !mounted) {
      return _lastOptions;
    }
    final results = await ref
        .read(placeSearchProvider)
        .search(text, language: appLanguageCode);
    if (_latestQuery != text) {
      return _lastOptions;
    }
    return _lastOptions = results;
  }

  bool _isMapped(String text) {
    return text == _pickedLabel ||
        text == widget.mappedLabel ||
        MoroccoRouteCoordinates.lookup(text) != null;
  }

  @override
  Widget build(BuildContext context) {
    final showsAttribution =
        ref.watch(placeSearchProvider) is PhotonPlaceSearch;
    return RawAutocomplete<PlaceSuggestion>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      displayStringForOption: (option) => option.label,
      optionsBuilder: _options,
      onSelected: (option) {
        setState(() => _pickedLabel = option.label);
        widget.onPicked?.call(option);
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, child) {
            final text = value.text.trim();
            final unmapped = text.length >= 2 && !_isMapped(text);
            return TextFormField(
              key: widget.fieldKey,
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              maxLength: 80,
              buildCounter:
                  (
                    context, {
                    required currentLength,
                    required isFocused,
                    required maxLength,
                  }) => null,
              decoration: InputDecoration(
                labelText: widget.label,
                prefixIcon: Icon(widget.icon),
                helperText: unmapped
                    ? tr('This place will not appear on the map.')
                    : null,
              ),
              validator: widget.validator,
            );
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 2,
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 300,
                maxWidth: MediaQuery.sizeOf(context).width - AppSpacing.lg * 2,
              ),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    ListTile(
                      dense: true,
                      leading: const Icon(Icons.location_on_outlined),
                      title: Text(option.label),
                      subtitle: option.detail == null
                          ? null
                          : Text(
                              option.detail!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      onTap: () => onSelected(option),
                    ),
                  // OpenStreetMap's licence asks for this wherever its data shows.
                  if (showsAttribution)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.xxs,
                        AppSpacing.md,
                        AppSpacing.xs,
                      ),
                      child: Text(
                        tr('Places © OpenStreetMap contributors'),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
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
}
