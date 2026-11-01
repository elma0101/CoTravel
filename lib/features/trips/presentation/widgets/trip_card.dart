import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/trip.dart';
import '../trip_formatters.dart';
import 'mountain_illustration.dart';
import 'trip_cover_images.dart';
import 'trip_photo_attribution.dart';

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
                  Text(
                    trip.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    trip.routeSummary,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    '${formatTripDateRange(trip.startDate, trip.endDate)} · '
                    '${trip.capacity} travelers max',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _HostAndPrice(trip: trip),
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
      return Stack(
        children: [
          const MountainIllustration(),
          Positioned(
            top: AppSpacing.sm,
            left: AppSpacing.sm,
            child: _SeatsLabel(trip: trip),
          ),
        ],
      );
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
                  const MountainIllustration(),
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
              child: _SeatsLabel(trip: trip),
            ),
            Positioned(
              top: AppSpacing.xs,
              right: AppSpacing.xs,
              child: TripPhotoAttributionButton(photo: photo),
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

class _SeatsLabel extends StatelessWidget {
  const _SeatsLabel({required this.trip});

  final Trip trip;

  String get _label {
    if (trip.isCancelled) {
      return 'Cancelled';
    }
    return switch (trip.openSeats) {
      0 => 'Full',
      1 => '1 seat left',
      final seats => '$seats seats left',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _label,
        style: const TextStyle(
          color: AppColors.ink,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _HostAndPrice extends StatelessWidget {
  const _HostAndPrice({required this.trip});

  final Trip trip;

  String get _initials {
    final parts = trip.hostName
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2);
    return parts.map((part) => part[0].toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final muted = textTheme.bodySmall?.copyWith(color: AppColors.muted);
    return Row(
      children: [
        CircleAvatar(
          radius: 18,
          backgroundColor: AppColors.terracottaSoft,
          child: Text(
            _initials,
            style: textTheme.labelMedium?.copyWith(color: AppColors.ink),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(trip.hostName, style: textTheme.titleSmall),
              Text(
                trip.hostVerified ? 'LinkedIn verified' : 'Not verified yet',
                style: muted,
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              formatTripMoney(trip.estimatedFullGroupShare, trip.currency),
              style: textTheme.titleSmall,
            ),
            Text('estimated', style: muted),
          ],
        ),
      ],
    );
  }
}
