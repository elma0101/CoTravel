import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/trip.dart';
import '../trip_formatters.dart';
import 'trip_cover_images.dart';

class TripCard extends StatelessWidget {
  const TripCard({required this.trip, required this.onTap, super.key});

  final Trip trip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TripCover(trip: trip),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          trip.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      _HostBadge(verified: trip.hostVerified),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${trip.originCity} to ${trip.destinationCity}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.xs,
                    children: [
                      _TripFact(
                        icon: Icons.calendar_today_outlined,
                        label: formatTripDate(trip.startDate),
                      ),
                      _TripFact(
                        icon: Icons.event_seat_outlined,
                        label:
                            '${trip.openSeats} ${trip.openSeats == 1 ? 'seat' : 'seats'}',
                      ),
                      _TripFact(
                        icon: Icons.payments_outlined,
                        label:
                            '${formatTripMoney(trip.estimatedFullGroupShare, trip.currency)} each',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TripCover extends StatelessWidget {
  const _TripCover({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final photo = TripCoverImages.forTrip(trip);
    if (photo == null) {
      return _RouteBanner(trip: trip);
    }

    return Semantics(
      image: true,
      label: photo.semanticLabel,
      child: SizedBox(
        height: 148,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              photo.assetPath,
              alignment: photo.alignment,
              fit: BoxFit.cover,
              cacheWidth: 1280,
              excludeFromSemantics: true,
              errorBuilder: (context, error, stackTrace) =>
                  _RouteBanner(trip: trip),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black12, Colors.transparent, Colors.black87],
                  stops: [0, 0.46, 1],
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.sm,
              child: _ImageLabel(label: trip.travelStyle.toUpperCase()),
            ),
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: _PhotoInfoButton(photo: photo),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.md,
              child: Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: Colors.white,
                    size: 17,
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Expanded(
                    child: Text(
                      photo.placeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        shadows: [Shadow(color: Colors.black54, blurRadius: 5)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageLabel extends StatelessWidget {
  const _ImageLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.05,
        ),
      ),
    );
  }
}

class _PhotoInfoButton extends StatelessWidget {
  const _PhotoInfoButton({required this.photo});

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

class _RouteBanner extends StatelessWidget {
  const _RouteBanner({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      padding: const EdgeInsets.all(AppSpacing.md),
      color: AppColors.greenSoft,
      child: Stack(
        children: [
          Positioned(
            right: -16,
            top: -28,
            child: Container(
              width: 104,
              height: 104,
              decoration: const BoxDecoration(
                color: AppColors.terracottaSoft,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                trip.travelStyle.toUpperCase(),
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                ),
              ),
              Row(
                children: [
                  const Icon(
                    Icons.trip_origin_rounded,
                    color: AppColors.green,
                    size: 16,
                  ),
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xs,
                      ),
                      color: AppColors.green,
                    ),
                  ),
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.terracotta,
                    size: 23,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HostBadge extends StatelessWidget {
  const _HostBadge({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Icon(
      verified ? Icons.verified_rounded : Icons.person_outline_rounded,
      color: verified ? AppColors.green : AppColors.muted,
      size: 20,
      semanticLabel: verified ? 'Verified host' : 'Host',
    );
  }
}

class _TripFact extends StatelessWidget {
  const _TripFact({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.green),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}
