import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import 'trip_cover_images.dart';

class TripPhotoAttributionButton extends StatelessWidget {
  const TripPhotoAttributionButton({required this.photo, super.key});

  final TripCoverPhoto photo;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.5),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Photo details',
        visualDensity: VisualDensity.compact,
        onPressed: () => _showPhotoDetails(context, photo),
        icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
      ),
    );
  }
}

void _showPhotoDetails(BuildContext context, TripCoverPhoto photo) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                photo.placeLabel,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Photo by ${photo.photographer} · ${photo.licenseName}',
                style: Theme.of(
                  sheetContext,
                ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: AppSpacing.xs),
              const Text(
                'Wikimedia preview resized for the app and displayed with a crop.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => unawaited(
                        _openPhotoLink(sheetContext, photo.licenseUrl),
                      ),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('License'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => unawaited(
                        _openPhotoLink(sheetContext, photo.sourceUrl),
                      ),
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text('Source'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

Future<void> _openPhotoLink(BuildContext context, String value) async {
  var opened = false;
  try {
    opened = await launchUrl(
      Uri.parse(value),
      mode: LaunchMode.externalApplication,
    );
  } on Object {
    opened = false;
  }
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Could not open this link.')));
  }
}
