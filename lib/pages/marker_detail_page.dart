import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/marker.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fake_map.dart';
import '../widgets/voice_player_bar.dart';

/// 标记详情页（UI Demo）。
class MarkerDetailPage extends StatelessWidget {
  const MarkerDetailPage({super.key, required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          _PhotoHeader(mark: mark),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(mark.name,
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      for (final String tag in mark.tags) TagPill(tag: tag),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '记录于 ${mark.createdAt.year}年${mark.createdAt.month}月'
                    '${mark.createdAt.day}日 '
                    '${mark.createdAt.hour.toString().padLeft(2, '0')}:'
                    '${mark.createdAt.minute.toString().padLeft(2, '0')}'
                    ' · ${mark.relativeTime(DemoData.now)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _LocationBlock(mark: mark),
                  if (mark.hasVoice) ...<Widget>[
                    const SizedBox(height: 14),
                    _VoiceBlock(mark: mark),
                  ],
                  if (mark.note.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 14),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const SectionLabel(
                            icon: Icons.notes_outlined,
                            title: '备注',
                          ),
                          const SizedBox(height: 10),
                          Text(
                            mark.note,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (mark.photos.length > 1) ...<Widget>[
                    const SizedBox(height: 14),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionLabel(
                            icon: Icons.photo_camera_outlined,
                            title: '照片',
                            trailing: Text(
                              '${mark.photos.length} 张',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 78,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: mark.photos.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, int i) => PhotoThumb(
                                photo: mark.photos[i],
                                size: 78,
                                showLabel: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _toast(context, '编辑（Demo 未实现）'),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.divider),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: FilledButton.icon(
                          onPressed: () => _toast(context, '导航（Demo 未实现）'),
                          icon: const Icon(Icons.navigation_outlined, size: 18),
                          label: const Text('导航到这里'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PhotoHeader extends StatelessWidget {
  const _PhotoHeader({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 240,
      pinned: true,
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      leading: const _GlassBackButton(),
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: _GlassIcon(
            icon: Icons.ios_share,
            onTap: () => _toast(context, '分享（Demo 未实现）'),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: mark.photos.isEmpty
            ? const FakeMap(seed: 5)
            : Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DecoratedBox(
                    decoration:
                        BoxDecoration(gradient: mark.photos.first.gradient),
                  ),
                  Center(
                    child: Icon(
                      mark.photos.first.icon,
                      size: 76,
                      color: Colors.white.withOpacity(0.85),
                    ),
                  ),
                  Positioned(
                    right: 14,
                    bottom: 14,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '1 / ${mark.photos.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
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

class _GlassBackButton extends StatelessWidget {
  const _GlassBackButton();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: _GlassIcon(
        icon: Icons.arrow_back,
        onTap: () => Navigator.of(context).maybePop(),
      ),
    );
  }
}

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.white.withOpacity(0.9),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 36,
            height: 36,
            child: Icon(icon, size: 18, color: AppColors.textPrimary),
          ),
        ),
      ),
    );
  }
}

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
            child: SizedBox(
              height: 130,
              child: FakeMap(seed: mark.id.hashCode & 0xff),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.place, size: 18, color: AppColors.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        mark.address,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mark.coordinateText,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => _toast(context, '已复制坐标（Demo）'),
                  child: const Icon(Icons.copy_outlined,
                      size: 17, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceBlock extends StatelessWidget {
  const _VoiceBlock({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    final VoiceNote voice = mark.voiceNote!;
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            icon: Icons.graphic_eq,
            title: '语音备注',
            trailing: Text(
              voice.durationText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          VoicePlayerBar(voiceNote: voice, seed: mark.id.hashCode & 0x7f),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Icon(Icons.text_fields,
                        size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: 5),
                    Text(
                      '语音转文字',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textTertiary,
                          ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  voice.transcript,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
