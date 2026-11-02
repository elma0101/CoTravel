import 'package:flutter/material.dart';

import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/app_spacing.dart';
import '../../../../core/l10n/app_strings.dart';
import '../../domain/trip.dart';
import 'trip_photo_image.dart';

/// The host's optional trip photos: ones already saved, then new picks.
class TripPhotosEditor extends StatelessWidget {
  const TripPhotosEditor({
    required this.kept,
    required this.added,
    required this.onAdd,
    required this.onRemoveKept,
    required this.onRemoveAdded,
    super.key,
  });

  final List<TripPhoto> kept;
  final List<NewTripPhoto> added;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemoveKept;
  final ValueChanged<int> onRemoveAdded;

  static const _size = 96.0;

  @override
  Widget build(BuildContext context) {
    final count = kept.length + added.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                tr('Photos (optional)'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Text(
              '$count/${Trip.maxPhotos}',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          tr(
            'Show the places on this route. The first photo is the cover, and everyone who can see the trip can see them.',
          ),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: _size,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var index = 0; index < kept.length; index++)
                _Thumbnail(
                  image: tripPhotoProvider(kept[index]),
                  isCover: index == 0,
                  onRemove: () => onRemoveKept(index),
                ),
              for (var index = 0; index < added.length; index++)
                _Thumbnail(
                  image: MemoryImage(added[index].bytes),
                  isCover: kept.isEmpty && index == 0,
                  onRemove: () => onRemoveAdded(index),
                ),
              if (count < Trip.maxPhotos)
                SizedBox.square(
                  dimension: _size,
                  child: OutlinedButton(
                    key: const ValueKey('trip-add-photos'),
                    onPressed: onAdd,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_photo_alternate_outlined),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(
                          tr('Add'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({
    required this.image,
    required this.isCover,
    required this.onRemove,
  });

  final ImageProvider<Object> image;
  final bool isCover;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: SizedBox.square(
        dimension: TripPhotosEditor._size,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image(
                image: image,
                fit: BoxFit.cover,
                semanticLabel: isCover ? tr('Cover photo') : tr('Trip photo'),
                errorBuilder: (context, error, stackTrace) =>
                    const ColoredBox(color: AppColors.greenSoft),
              ),
            ),
            if (isCover)
              Positioned(
                left: AppSpacing.xxs,
                bottom: AppSpacing.xxs,
                child: ExcludeSemantics(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxs,
                        vertical: 2,
                      ),
                      child: Text(
                        tr('Cover'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              right: 0,
              child: IconButton(
                onPressed: onRemove,
                tooltip: tr('Remove photo'),
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                padding: EdgeInsets.zero,
                icon: const CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.black54,
                  child: Icon(
                    Icons.close_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
