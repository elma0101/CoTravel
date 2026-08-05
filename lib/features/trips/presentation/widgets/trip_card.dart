import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../domain/trip.dart';
import '../trip_formatters.dart';

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
            _RouteBanner(trip: trip),
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
