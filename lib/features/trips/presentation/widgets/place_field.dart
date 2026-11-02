import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../domain/trip_route.dart';

/// A city field that suggests places the route map can show. Other names are
/// still accepted, and the field says they will not appear on the map.
class PlaceField extends StatefulWidget {
  const PlaceField({
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    required this.validator,
    super.key,
  });

  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final FormFieldValidator<String> validator;

  @override
  State<PlaceField> createState() => _PlaceFieldState();
}

class _PlaceFieldState extends State<PlaceField> {
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        final matches = MoroccoRouteCoordinates.search(value.text);
        // No point suggesting what is already typed in full.
        return matches.length == 1 &&
                matches.first.toLowerCase() == value.text.trim().toLowerCase()
            ? const []
            : matches;
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
        return ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, value, child) {
            final text = value.text.trim();
            final unmapped =
                text.length >= 2 &&
                MoroccoRouteCoordinates.lookup(text) == null;
            return TextFormField(
              key: widget.fieldKey,
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
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
                maxHeight: 240,
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
                      title: Text(option),
                      onTap: () => onSelected(option),
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
