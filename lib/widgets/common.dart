import 'package:flutter/material.dart';

import '../models/marker.dart';
import '../theme/app_theme.dart';

/// 照片占位：Demo 里不接图库，用渐变 + 图标模拟一张照片。
class PhotoThumb extends StatelessWidget {
  const PhotoThumb({
    super.key,
    required this.photo,
    this.size = 84,
    this.radius = AppRadius.md,
    this.showLabel = false,
  });

  final DemoPhoto photo;
  final double size;
  final double radius;
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: photo.gradient,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(photo.icon, color: Colors.white.withOpacity(0.92), size: size * 0.34),
          if (showLabel) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              photo.label,
              style: TextStyle(
                color: Colors.white.withOpacity(0.92),
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 标签小药丸。
class TagPill extends StatelessWidget {
  const TagPill({super.key, required this.tag, this.dense = false});

  final String tag;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.tagColor(tag);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 8 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Text(
        tag,
        style: TextStyle(
          color: color,
          fontSize: dense ? 11.5 : 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 白底圆角卡片，页面里所有分组都用它。
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: kCardShadow,
      ),
      child: child,
    );
  }
}

/// 表单里的小标题：图标 + 标题 +（可选）右侧说明。
class SectionLabel extends StatelessWidget {
  const SectionLabel({
    super.key,
    required this.icon,
    required this.title,
    this.trailing,
    this.required = false,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 17, color: AppColors.primary),
        const SizedBox(width: 7),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        if (required)
          const Padding(
            padding: EdgeInsets.only(left: 3),
            child: Text(
              '*',
              style: TextStyle(color: AppColors.danger, fontSize: 14),
            ),
          ),
        const Spacer(),
        if (trailing != null) trailing!,
      ],
    );
  }
}
