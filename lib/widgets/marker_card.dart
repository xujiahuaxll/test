import 'package:flutter/material.dart';

import '../models/location_mark.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// 列表中的一条标记。
class MarkerCard extends StatelessWidget {
  const MarkerCard({
    super.key,
    required this.mark,
    this.onTap,
    this.onLongPress,
    this.onNavigate,
  });

  final LocationMark mark;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onNavigate;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: kCardShadow,
            color: AppColors.surface,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Thumb(mark: mark),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            mark.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          mark.relativeTime(),
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppColors.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Expanded(
                          child: Text(
                            mark.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ),
                      ],
                    ),
                    if (mark.tags.isNotEmpty || mark.hasVoice) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[
                          for (final String tag in mark.tags)
                            TagPill(tag: tag, dense: true),
                          if (mark.hasVoice) _VoiceBadge(mark: mark),
                        ],
                      ),
                    ],
                    if (mark.note.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Text(
                        mark.note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(height: 1.4),
                      ),
                    ],
                  ],
                ),
              ),
              if (onNavigate != null) ...<Widget>[
                const SizedBox(width: 6),
                _NavigateButton(onTap: onNavigate!),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    if (mark.photoPaths.isEmpty) {
      return Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: const Icon(
          Icons.place_outlined,
          color: AppColors.primary,
          size: 26,
        ),
      );
    }

    return Stack(
      children: <Widget>[
        PhotoThumb(relativePath: mark.photoPaths.first, size: 86),
        if (mark.photoPaths.length > 1)
          Positioned(
            right: 5,
            bottom: 5,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.photo_library_outlined,
                      size: 10, color: Colors.white),
                  const SizedBox(width: 3),
                  Text(
                    '${mark.photoPaths.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _VoiceBadge extends StatelessWidget {
  const _VoiceBadge({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.graphic_eq, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            mark.durationText,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡片右侧的导航按钮，点一下唤起本机地图应用。
class _NavigateButton extends StatelessWidget {
  const _NavigateButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '导航到这里',
      child: Material(
        color: AppColors.primarySoft,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: const SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              Icons.navigation_outlined,
              size: 19,
              color: AppColors.primary,
            ),
          ),
        ),
      ),
    );
  }
}
