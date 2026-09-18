import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/marker_repository.dart';
import '../models/location_mark.dart';
import '../services/media_store.dart';
import '../theme/app_theme.dart';
import '../widgets/amap_preview.dart';
import '../widgets/common.dart';
import '../widgets/fake_map.dart';
import '../widgets/voice_player_bar.dart';
import 'add_marker_page.dart';

/// 标记详情。支持编辑、删除、查看大图、播放录音。
class MarkerDetailPage extends StatefulWidget {
  const MarkerDetailPage({super.key, required this.mark});

  final LocationMark mark;

  @override
  State<MarkerDetailPage> createState() => _MarkerDetailPageState();
}

class _MarkerDetailPageState extends State<MarkerDetailPage> {
  late LocationMark _mark = widget.mark;
  final PageController _photoController = PageController();
  int _photoIndex = 0;

  @override
  void dispose() {
    _photoController.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    final LocationMark? updated = await Navigator.of(context).push(
      MaterialPageRoute<LocationMark>(
        builder: (_) => AddMarkerPage(existing: _mark),
      ),
    );
    if (updated == null || !mounted) return;
    final LocationMark? fresh =
        await MarkerRepository.instance.findById(updated.id);
    if (!mounted || fresh == null) return;
    setState(() {
      _mark = fresh;
      _photoIndex = 0;
    });
  }

  Future<void> _delete() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除标记'),
        content: Text('确定删除「${_mark.name}」吗？照片和录音会一起删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await MarkerRepository.instance.delete(_mark);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _copyCoordinate() async {
    await Clipboard.setData(ClipboardData(text: _mark.coordinateText));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('坐标已复制')));
  }

  void _openPhoto(int index) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _PhotoViewerPage(
          paths: _mark.photoPaths,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocationMark mark = _mark;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: AppColors.surface,
            surfaceTintColor: Colors.transparent,
            leading: _GlassIcon(
              icon: Icons.arrow_back,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            actions: <Widget>[
              _GlassIcon(icon: Icons.edit_outlined, onTap: _edit),
              const SizedBox(width: 8),
              _GlassIcon(
                icon: Icons.delete_outline,
                onTap: _delete,
                color: AppColors.danger,
              ),
              const SizedBox(width: 12),
            ],
            flexibleSpace: FlexibleSpaceBar(
              // 没有照片时头图用本地绘制的示意图：
              // 下面的位置卡片已经是真实地图，同屏再开一个原生地图太重。
              background: mark.photoPaths.isEmpty
                  ? FakeMap(
                      seed: ((mark.latitude + mark.longitude) * 1000).round(),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[
                        PageView.builder(
                          controller: _photoController,
                          itemCount: mark.photoPaths.length,
                          onPageChanged: (int i) =>
                              setState(() => _photoIndex = i),
                          itemBuilder: (BuildContext context, int index) {
                            return GestureDetector(
                              onTap: () => _openPhoto(index),
                              child: Image.file(
                                File(MediaStore.instance
                                    .absolute(mark.photoPaths[index])),
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: AppColors.primarySoft,
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: AppColors.primary,
                                    size: 40,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (mark.photoPaths.length > 1)
                          Positioned(
                            right: 14,
                            bottom: 14,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.35),
                                borderRadius:
                                    BorderRadius.circular(AppRadius.pill),
                              ),
                              child: Text(
                                '${_photoIndex + 1} / ${mark.photoPaths.length}',
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
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(mark.name,
                      style: Theme.of(context).textTheme.headlineSmall),
                  if (mark.tags.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        for (final String tag in mark.tags) TagPill(tag: tag),
                      ],
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    '记录于 ${_formatDateTime(mark.createdAt)} · '
                    '${mark.relativeTime()}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  _LocationBlock(mark: mark, onCopy: _copyCoordinate),
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
                          SelectableText(
                            mark.note,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (mark.photoPaths.length > 1) ...<Widget>[
                    const SizedBox(height: 14),
                    SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          SectionLabel(
                            icon: Icons.photo_camera_outlined,
                            title: '照片',
                            trailing: Text(
                              '${mark.photoPaths.length} 张',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            height: 78,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: mark.photoPaths.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, int i) => GestureDetector(
                                onTap: () => _openPhoto(i),
                                child: PhotoThumb(
                                  relativePath: mark.photoPaths[i],
                                  size: 78,
                                ),
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
                          onPressed: _copyCoordinate,
                          icon: const Icon(Icons.copy_outlined, size: 18),
                          label: const Text('复制坐标'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.divider),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _edit,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('编辑'),
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

String _formatDateTime(DateTime time) =>
    '${time.year}年${time.month}月${time.day}日 '
    '${time.hour.toString().padLeft(2, '0')}:'
    '${time.minute.toString().padLeft(2, '0')}';

class _GlassIcon extends StatelessWidget {
  const _GlassIcon({
    required this.icon,
    required this.onTap,
    this.color = AppColors.textPrimary,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color color;

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
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _LocationBlock extends StatelessWidget {
  const _LocationBlock({required this.mark, required this.onCopy});

  final LocationMark mark;
  final VoidCallback onCopy;

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
              child: AMapPreview(
                latitude: mark.latitude,
                longitude: mark.longitude,
              ),
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
                        mark.address?.isNotEmpty == true
                            ? mark.address!
                            : '未获取到地址',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mark.accuracy == null
                            ? mark.coordinateText
                            : '${mark.coordinateText} · 精度 '
                                '${mark.accuracy!.round()} 米',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onCopy,
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
    final String? raw = mark.transcript;
    // 备注默认就是转写文字，两者一致时没必要再展示一遍原文。
    final String? transcript =
        raw != null && raw.trim() != mark.note.trim() ? raw : null;

    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            icon: Icons.graphic_eq,
            title: '语音备注',
            trailing: Text(
              mark.durationText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          VoicePlayerBar(
            relativePath: mark.audioPath!,
            duration: mark.audioDuration,
            waveform: mark.waveform,
          ),
          if (transcript != null && transcript.isNotEmpty) ...<Widget>[
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
                        '语音转文字原文',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textTertiary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    transcript,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 全屏看图。
class _PhotoViewerPage extends StatelessWidget {
  const _PhotoViewerPage({required this.paths, required this.initialIndex});

  final List<String> paths;
  final int initialIndex;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: PageView.builder(
        controller: PageController(initialPage: initialIndex),
        itemCount: paths.length,
        itemBuilder: (BuildContext context, int index) {
          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: Image.file(
                File(MediaStore.instance.absolute(paths[index])),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.broken_image_outlined,
                  color: Colors.white54,
                  size: 48,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
