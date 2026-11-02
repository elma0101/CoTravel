import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../../trips/domain/trip.dart';
import '../../../trips/presentation/trip_formatters.dart';
import '../../../trips/presentation/widgets/mountain_illustration.dart';
import '../../../trips/presentation/widgets/trip_cover_images.dart';
import '../../../trips/presentation/widgets/trip_photo_attribution.dart';
import '../../../trips/presentation/widgets/trip_photo_image.dart';

/// Trips as a stack of full cards: swipe right to save, left to skip, tap to
/// open. Buttons do the same for people who prefer not to swipe.
class TripSwipeDeck extends StatefulWidget {
  const TripSwipeDeck({
    required this.trips,
    required this.isSaved,
    required this.onOpen,
    required this.onSave,
    required this.emptyState,
    super.key,
  });

  final List<Trip> trips;
  final bool Function(Trip trip) isSaved;
  final ValueChanged<Trip> onOpen;
  final ValueChanged<Trip> onSave;

  /// Shown once every trip has been swiped, given a way to start over.
  final Widget Function(VoidCallback startOver) emptyState;

  @override
  State<TripSwipeDeck> createState() => _TripSwipeDeckState();
}

enum _Swipe { save, skip }

class _TripSwipeDeckState extends State<TripSwipeDeck>
    with SingleTickerProviderStateMixin {
  static const _flyDuration = Duration(milliseconds: 260);

  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: _flyDuration,
  );
  int _position = 0;
  Offset _drag = Offset.zero;
  Offset _from = Offset.zero;
  Offset _to = Offset.zero;
  _Swipe? _flying;

  @override
  void initState() {
    super.initState();
    _animation.addListener(() {
      setState(() {
        _drag = Offset.lerp(
          _from,
          _to,
          Curves.easeOut.transform(_animation.value),
        )!;
      });
    });
  }

  @override
  void didUpdateWidget(TripSwipeDeck oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIds = oldWidget.trips.map((trip) => trip.id).toList();
    final newIds = widget.trips.map((trip) => trip.id).toList();
    // New filters mean a new deck; saving a trip does not change the order.
    if (oldIds.join() != newIds.join()) {
      final current = _current;
      final kept = current == null ? -1 : newIds.indexOf(current.id);
      _position = kept == -1 ? 0 : kept;
      _drag = Offset.zero;
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  Trip? get _current =>
      _position < widget.trips.length ? widget.trips[_position] : null;

  Future<void> _animateTo(Offset target) async {
    _from = _drag;
    _to = target;
    await _animation.forward(from: 0);
  }

  Future<void> _swipe(_Swipe direction, {required double width}) async {
    final trip = _current;
    if (trip == null || _flying != null) {
      return;
    }
    _flying = direction;
    unawaited(
      direction == _Swipe.save
          ? HapticFeedback.mediumImpact()
          : HapticFeedback.lightImpact(),
    );
    final sign = direction == _Swipe.save ? 1 : -1;
    await _animateTo(Offset(sign * width * 1.4, _drag.dy + 40));
    if (!mounted) {
      return;
    }
    if (direction == _Swipe.save && !widget.isSaved(trip)) {
      widget.onSave(trip);
    }
    setState(() {
      _position++;
      _drag = Offset.zero;
      _flying = null;
    });
  }

  void _undo() {
    if (_position == 0 || _flying != null) {
      return;
    }
    unawaited(HapticFeedback.selectionClick());
    setState(() {
      _position--;
      _drag = Offset.zero;
    });
  }

  void _startOver() => setState(() => _position = 0);

  @override
  Widget build(BuildContext context) {
    final trip = _current;
    if (trip == null) {
      return widget.emptyState(_startOver);
    }
    final next = _position + 1 < widget.trips.length
        ? widget.trips[_position + 1]
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final threshold = width * 0.28;
        final progress = (_drag.dx.abs() / threshold).clamp(0.0, 1.0);
        return Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  if (next != null)
                    Positioned.fill(
                      // Only the top card can be tapped or read out.
                      child: IgnorePointer(
                        child: ExcludeSemantics(
                          child: Transform.scale(
                            scale: 0.94 + 0.06 * progress,
                            child: _TripSwipeCard(
                              key: ValueKey('swipe-card-behind-${next.id}'),
                              trip: next,
                              saved: widget.isSaved(next),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Positioned.fill(
                    child: GestureDetector(
                      key: ValueKey('swipe-card-${trip.id}'),
                      onTap: () => widget.onOpen(trip),
                      onPanUpdate: (details) {
                        if (_flying == null) {
                          setState(() => _drag += details.delta);
                        }
                      },
                      onPanEnd: (details) {
                        final velocity = details.velocity.pixelsPerSecond.dx;
                        if (_drag.dx > threshold || velocity > 900) {
                          unawaited(_swipe(_Swipe.save, width: width));
                        } else if (_drag.dx < -threshold || velocity < -900) {
                          unawaited(_swipe(_Swipe.skip, width: width));
                        } else {
                          unawaited(_animateTo(Offset.zero));
                        }
                      },
                      child: Transform.translate(
                        offset: _drag,
                        child: Transform.rotate(
                          angle: _drag.dx / width * 0.35,
                          child: _TripSwipeCard(
                            trip: trip,
                            saved: widget.isSaved(trip),
                            stamp: _drag.dx > 8
                                ? _Swipe.save
                                : _drag.dx < -8
                                ? _Swipe.skip
                                : null,
                            stampOpacity: progress,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _RoundAction(
                  key: const ValueKey('swipe-undo'),
                  icon: Icons.replay_rounded,
                  tooltip: tr('Back to the last trip'),
                  size: 48,
                  onPressed: _position == 0 ? null : _undo,
                ),
                _RoundAction(
                  key: const ValueKey('swipe-skip'),
                  icon: Icons.close_rounded,
                  tooltip: tr('Skip'),
                  color: AppColors.terracotta,
                  size: 64,
                  onPressed: () => _swipe(_Swipe.skip, width: width),
                ),
                _RoundAction(
                  key: const ValueKey('swipe-save'),
                  icon: Icons.favorite_rounded,
                  tooltip: tr('Save'),
                  color: AppColors.green,
                  size: 64,
                  onPressed: () => _swipe(_Swipe.save, width: width),
                ),
                _RoundAction(
                  key: const ValueKey('swipe-open'),
                  icon: Icons.info_outline_rounded,
                  tooltip: tr('See details'),
                  size: 48,
                  onPressed: () => widget.onOpen(trip),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              tr('{position} of {count}', {
                'position': _position + 1,
                'count': widget.trips.length,
              }),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.muted),
            ),
          ],
        );
      },
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.tooltip,
    required this.size,
    required this.onPressed,
    this.color = AppColors.muted,
    super.key,
  });

  final IconData icon;
  final String tooltip;
  final double size;
  final VoidCallback? onPressed;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: IconButton.outlined(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: size * 0.45,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.surface,
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4), width: 1.5),
          elevation: 2,
          shadowColor: Colors.black26,
        ),
        icon: Icon(icon),
      ),
    );
  }
}

class _TripSwipeCard extends StatelessWidget {
  const _TripSwipeCard({
    required this.trip,
    required this.saved,
    this.stamp,
    this.stampOpacity = 0,
    super.key,
  });

  final Trip trip;
  final bool saved;
  final _Swipe? stamp;
  final double stampOpacity;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    const white = TextStyle(color: Colors.white);
    final seats = switch (trip.openSeats) {
      0 => tr('Full'),
      1 => tr('1 seat left'),
      final seats => tr('{seats} seats left', {'seats': seats}),
    };
    return Material(
      elevation: 3,
      shadowColor: Colors.black38,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          _CoverBackground(trip: trip),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black26, Colors.transparent, Colors.black87],
                stops: [0, 0.4, 0.92],
              ),
            ),
          ),
          Positioned(
            top: AppSpacing.md,
            left: AppSpacing.md,
            right: AppSpacing.xxl,
            child: Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _Pill(text: seats),
                if (saved)
                  _Pill(
                    icon: Icons.favorite_rounded,
                    text: tr('Saved for later'),
                  ),
              ],
            ),
          ),
          if (stamp != null)
            Positioned(
              top: AppSpacing.xxl,
              left: stamp == _Swipe.save ? AppSpacing.lg : null,
              right: stamp == _Swipe.skip ? AppSpacing.lg : null,
              child: Opacity(
                opacity: stampOpacity,
                child: Transform.rotate(
                  angle: stamp == _Swipe.save ? -0.25 : 0.25,
                  child: _Stamp(save: stamp == _Swipe.save),
                ),
              ),
            ),
          Positioned(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            bottom: AppSpacing.lg,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  trip.routeSummary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyLarge?.merge(white),
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xs,
                  runSpacing: AppSpacing.xs,
                  children: [
                    _Pill(
                      icon: Icons.calendar_today_outlined,
                      text: formatTripDateRange(trip.startDate, trip.endDate),
                    ),
                    _Pill(text: tr(trip.travelStyle)),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                              trip.hostName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleSmall?.merge(white),
                            ),
                          ),
                          if (trip.hostVerified) ...[
                            const SizedBox(width: AppSpacing.xxs),
                            Icon(
                              Icons.verified_rounded,
                              size: 18,
                              color: Colors.white,
                              semanticLabel: tr('LinkedIn verified'),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              formatTripMoney(
                                trip.estimatedFullGroupShare,
                                trip.currency,
                              ),
                              style: textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              tr('per person, estimated'),
                              style: textTheme.bodySmall?.copyWith(
                                color: Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverBackground extends StatelessWidget {
  const _CoverBackground({required this.trip});

  final Trip trip;

  @override
  Widget build(BuildContext context) {
    // The host's own photo first, then a built-in photo, then the drawing.
    final hostPhoto = trip.photos.firstOrNull;
    if (hostPhoto != null) {
      return Image(
        image: tripPhotoProvider(hostPhoto),
        fit: BoxFit.cover,
        semanticLabel: tr('Photo of {place}', {'place': trip.destinationCity}),
        errorBuilder: (context, error, stackTrace) =>
            const MountainIllustration(height: double.infinity),
      );
    }
    final photo = TripCoverImages.forTrip(trip);
    if (photo == null) {
      return const MountainIllustration(height: double.infinity);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          photo.assetPath,
          alignment: photo.alignment,
          fit: BoxFit.cover,
          cacheWidth: 1280,
          semanticLabel: tr(photo.semanticLabel),
          errorBuilder: (context, error, stackTrace) =>
              const MountainIllustration(height: double.infinity),
        ),
        Positioned(
          top: AppSpacing.xs,
          right: AppSpacing.xs,
          child: TripPhotoAttributionButton(photo: photo),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.ink),
            const SizedBox(width: AppSpacing.xxs),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Stamp extends StatelessWidget {
  const _Stamp({required this.save});

  final bool save;

  @override
  Widget build(BuildContext context) {
    final color = save ? AppColors.green : AppColors.terracotta;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        border: Border.all(color: color, width: 3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        save ? tr('SAVE') : tr('SKIP'),
        style: TextStyle(
          color: color,
          fontSize: 28,
          fontWeight: FontWeight.w800,
          letterSpacing: 2,
        ),
      ),
    );
  }
}
