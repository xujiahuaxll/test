import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';

import '../data/marker_repository.dart';
import '../models/location_mark.dart';
import '../services/location_service.dart';
import '../services/media_store.dart';
import '../theme/app_theme.dart';
import '../widgets/amap_preview.dart';
import '../widgets/common.dart';
import '../widgets/record_sheet.dart';
import '../widgets/voice_player_bar.dart';
import 'pick_location_page.dart';

/// 新建 / 编辑标记。新建时进入即自动定位。
class AddMarkerPage extends StatefulWidget {
  const AddMarkerPage({super.key, this.existing});

  /// 传入已有标记则进入编辑模式。
  final LocationMark? existing;

  @override
  State<AddMarkerPage> createState() => _AddMarkerPageState();
}

enum _LocateState { locating, located, failed }

enum _NoteMode { text, voice }

class _AddMarkerPageState extends State<AddMarkerPage> {
  static const Uuid _uuid = Uuid();

  final MarkerRepository _repo = MarkerRepository.instance;
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  _LocateState _locateState = _LocateState.locating;
  LocationFailure? _locateError;
  LocationResult? _location;

  _NoteMode _noteMode = _NoteMode.text;
  final Set<String> _selectedTags = <String>{};
  List<String> _availableTags = <String>[];
  final List<String> _photoPaths = <String>[];

  String? _audioPath;
  Duration? _audioDuration;
  List<double> _waveform = const <double>[];

  /// 语音识别出的原文。备注里的文字用户可以随意改，这里保留识别原文。
  String? _transcript;

  /// 编辑时被移除的媒体文件，保存成功后再真正删除。
  final List<String> _pendingDeletions = <String>[];
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _loadTags();

    final LocationMark? existing = widget.existing;
    if (existing != null) {
      _nameController.text = existing.name;
      _noteController.text = existing.note;
      _selectedTags.addAll(existing.tags);
      _photoPaths.addAll(existing.photoPaths);
      _audioPath = existing.audioPath;
      _audioDuration = existing.audioDuration;
      _waveform = existing.waveform;
      _transcript = existing.transcript;
      _noteMode = existing.hasVoice ? _NoteMode.voice : _NoteMode.text;
      _location = LocationResult(
        latitude: existing.latitude,
        longitude: existing.longitude,
        accuracy: existing.accuracy ?? 0,
        address: existing.address,
      );
      _locateState = _LocateState.located;
    } else {
      _locate();
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadTags() async {
    final List<String> tags = await _repo.allTags();
    if (!mounted) return;
    setState(() => _availableTags = tags);
  }

  /// 自动获取当前位置（系统 GPS + 系统逆地理编码）。
  Future<void> _locate() async {
    setState(() {
      _locateState = _LocateState.locating;
      _locateError = null;
    });
    try {
      final LocationResult result = await LocationService.instance.current();
      if (!mounted) return;
      setState(() {
        _location = result;
        _locateState = _LocateState.located;
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _locateError = failure;
        _locateState = _LocateState.failed;
      });
    }
  }

  /// 在高德地图上手动挪一下位置（自动定位不准时用）。
  Future<void> _pickOnMap() async {
    final LocationResult? current = _location;
    final LocationResult? picked = await PickLocationPage.show(
      context,
      latitude: current?.latitude ?? 39.909187,
      longitude: current?.longitude ?? 116.397451,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _location = picked;
      _locateState = _LocateState.located;
      _locateError = null;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final XFile? file = await _picker.pickImage(
        source: source,
        imageQuality: 85,
        maxWidth: 2048,
      );
      if (file == null) return;
      final String relative = await MediaStore.instance.importPhoto(file.path);
      if (!mounted) return;
      setState(() => _photoPaths.add(relative));
    } catch (e) {
      if (!mounted) return;
      _toast('打开${source == ImageSource.camera ? '相机' : '相册'}失败：$e');
    }
  }

  void _choosePhotoSource() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => _PhotoSourceSheet(
        onPick: (ImageSource source) {
          Navigator.of(sheetContext).pop();
          _pickPhoto(source);
        },
      ),
    );
  }

  Future<void> _record() async {
    final RecordResult? result = await RecordSheet.show(context);
    if (result == null || !mounted) return;

    final String? previous = _audioPath;
    if (previous != null && previous != result.relativePath) {
      _pendingDeletions.add(previous);
    }

    setState(() {
      _audioPath = result.relativePath;
      _audioDuration = result.duration;
      _waveform = result.waveform;
      _noteMode = _NoteMode.voice;

      final String text = result.transcript.trim();
      if (text.isNotEmpty) {
        _transcript = text;
        final String current = _noteController.text.trim();
        _noteController.text = current.isEmpty ? text : '$current\n$text';
      }
    });
  }

  void _deleteAudio() {
    final String? path = _audioPath;
    if (path == null) return;
    setState(() {
      _pendingDeletions.add(path);
      _audioPath = null;
      _audioDuration = null;
      _waveform = const <double>[];
      _transcript = null;
    });
  }

  Future<void> _addCustomTag() async {
    final TextEditingController controller = TextEditingController();
    final String? tag = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('新建标签'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 8,
          decoration: const InputDecoration(
            hintText: '例如：亲子、夜景',
            counterText: '',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            style: FilledButton.styleFrom(
              minimumSize: const Size(80, 40),
            ),
            child: const Text('添加'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (tag == null || tag.isEmpty) return;
    await _repo.addTag(tag);
    await _loadTags();
    if (!mounted) return;
    setState(() => _selectedTags.add(tag));
  }

  Future<void> _save() async {
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      _toast('请先填写标记名称');
      return;
    }
    final LocationResult? location = _location;
    if (location == null) {
      _toast('还没有拿到位置，请先完成定位');
      return;
    }

    setState(() => _saving = true);

    final DateTime now = DateTime.now();
    final LocationMark mark = LocationMark(
      id: widget.existing?.id ?? _uuid.v4(),
      name: name,
      tags: _selectedTags.toList(),
      address: location.address,
      latitude: location.latitude,
      longitude: location.longitude,
      accuracy: location.accuracy,
      photoPaths: List<String>.from(_photoPaths),
      note: _noteController.text.trim(),
      audioPath: _audioPath,
      audioDuration: _audioDuration,
      transcript: _audioPath == null ? null : _transcript,
      waveform: _waveform,
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    try {
      await _repo.save(mark);
      for (final String path in _pendingDeletions) {
        await MediaStore.instance.deleteFile(path);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('保存失败：$e');
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(mark);
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(_isEditing ? '编辑标记' : '新建标记'),
        actions: <Widget>[
          TextButton(
            onPressed: _saving ? null : _save,
            child: Text(
              '保存',
              style: TextStyle(
                color: _saving ? AppColors.textTertiary : AppColors.primary,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          _LocationCard(
            state: _locateState,
            location: _location,
            failure: _locateError,
            onRetry: _locate,
            onPick: _pickOnMap,
          ),
          const SizedBox(height: 14),
          _nameSection(),
          const SizedBox(height: 14),
          _tagSection(),
          const SizedBox(height: 14),
          _photoSection(),
          const SizedBox(height: 14),
          _noteSection(),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Colors.white,
                    ),
                  )
                : Text(_isEditing ? '保存修改' : '保存标记'),
          ),
        ],
      ),
    );
  }

  Widget _nameSection() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel(
            icon: Icons.drive_file_rename_outline,
            title: '标记名称',
            required: true,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            maxLength: 20,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '给这个地点起个名字，比如「江边观景台」',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagSection() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            icon: Icons.sell_outlined,
            title: '标记标签',
            trailing: Text(
              '已选 ${_selectedTags.length}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String tag in _availableTags)
                _SelectableTag(
                  tag: tag,
                  selected: _selectedTags.contains(tag),
                  onTap: () => setState(() {
                    if (!_selectedTags.remove(tag)) _selectedTags.add(tag);
                  }),
                ),
              _AddTagChip(onTap: _addCustomTag),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoSection() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SectionLabel(
            icon: Icons.photo_camera_outlined,
            title: '标记照片',
            trailing: Text(
              '${_photoPaths.length}/9',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photoPaths.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _AddPhotoButton(
                    onTap: _photoPaths.length >= 9
                        ? () => _toast('最多添加 9 张照片')
                        : _choosePhotoSource,
                  );
                }
                final int photoIndex = index - 1;
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    PhotoThumb(
                      relativePath: _photoPaths[photoIndex],
                      size: 86,
                    ),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _pendingDeletions.add(_photoPaths[photoIndex]);
                          _photoPaths.removeAt(photoIndex);
                        }),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.textPrimary.withOpacity(0.78),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.close,
                              size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _noteSection() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel(icon: Icons.notes_outlined, title: '标记备注'),
          const SizedBox(height: 12),
          _NoteModeSwitch(
            mode: _noteMode,
            onChanged: (_NoteMode mode) => setState(() => _noteMode = mode),
          ),
          const SizedBox(height: 14),
          if (_noteMode == _NoteMode.text) ...<Widget>[
            TextField(
              controller: _noteController,
              maxLines: 5,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: '写点什么，比如营业时间、停车位置、下次再来要注意的事…',
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '也可以直接说给它听，自动转成文字',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _record,
                  icon: const Icon(Icons.mic_none, size: 18),
                  label: const Text('语音输入'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ] else ...<Widget>[
            _VoiceNoteArea(
              relativePath: _audioPath,
              duration: _audioDuration,
              waveform: _waveform,
              onRecord: _record,
              onDelete: _deleteAudio,
            ),
            if (_audioPath != null) ...<Widget>[
              const SizedBox(height: 14),
              const Divider(),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  const Icon(Icons.text_fields,
                      size: 16, color: AppColors.textSecondary),
                  const SizedBox(width: 6),
                  Text(
                    '转写文字（可编辑）',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                maxLines: 4,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText: '识别结果会显示在这里，可以手动修改',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// 顶部定位卡片：定位中 / 定位成功 / 定位失败三种状态。
class _LocationCard extends StatelessWidget {
  const _LocationCard({
    required this.state,
    required this.location,
    required this.failure,
    required this.onRetry,
    required this.onPick,
  });

  final _LocateState state;
  final LocationResult? location;
  final LocationFailure? failure;
  final VoidCallback onRetry;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final LocationResult? result = location;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: kCardShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: <Widget>[
          SizedBox(
            height: 168,
            child: Stack(
              children: <Widget>[
                AMapPreview(
                  latitude: result?.latitude ?? 39.909187,
                  longitude: result?.longitude ?? 116.397451,
                  showHint: result != null,
                ),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _MapChip(
                    icon: switch (state) {
                      _LocateState.locating => Icons.gps_not_fixed,
                      _LocateState.located => Icons.gps_fixed,
                      _LocateState.failed => Icons.gps_off,
                    },
                    label: switch (state) {
                      _LocateState.locating => '定位中',
                      _LocateState.located =>
                        '已定位 · 精度 ${result?.accuracy.round() ?? 0} 米',
                      _LocateState.failed => '定位失败',
                    },
                    highlight: state == _LocateState.located,
                  ),
                ),
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 2,
                    child: InkWell(
                      onTap: onRetry,
                      customBorder: const CircleBorder(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.my_location,
                            size: 19, color: AppColors.primary),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: switch (state) {
              _LocateState.locating => Row(
                  children: <Widget>[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '正在获取当前位置…',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              _LocateState.failed => Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(Icons.error_outline,
                        size: 18, color: AppColors.danger),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        failure?.message ?? '定位失败',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    if (failure?.kind == LocationFailureKind.deniedForever)
                      const TextButton(
                        onPressed: openAppSettings,
                        child: Text('去设置'),
                      )
                    else
                      TextButton(onPressed: onRetry, child: const Text('重试')),
                  ],
                ),
              _LocateState.located => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Icon(Icons.place,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            result?.address?.isNotEmpty == true
                                ? result!.address!
                                : '未获取到地址（已记录坐标）',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            result == null
                                ? ''
                                : '${result.latitude.toStringAsFixed(6)}, '
                                    '${result.longitude.toStringAsFixed(6)}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                        ),
                        GestureDetector(
                          onTap: onPick,
                          child: const Text(
                            '手动调整',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
            },
          ),
        ],
      ),
    );
  }
}

class _MapChip extends StatelessWidget {
  const _MapChip({
    required this.icon,
    required this.label,
    this.highlight = false,
  });

  final IconData icon;
  final String label;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        boxShadow: kCardShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(
            icon,
            size: 14,
            color: highlight ? AppColors.primary : AppColors.textSecondary,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: highlight ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectableTag extends StatelessWidget {
  const _SelectableTag({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final String tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color color = AppColors.tagColor(tag);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: selected ? color : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (selected) ...<Widget>[
              Icon(Icons.check, size: 13, color: color),
              const SizedBox(width: 4),
            ],
            Text(
              tag,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? color : AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddTagChip extends StatelessWidget {
  const _AddTagChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppColors.divider, width: 1.2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.add, size: 14, color: AppColors.textSecondary),
            SizedBox(width: 4),
            Text(
              '自定义',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddPhotoButton extends StatelessWidget {
  const _AddPhotoButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 86,
        height: 86,
        decoration: BoxDecoration(
          color: AppColors.primarySoft.withOpacity(0.55),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.35),
            width: 1.2,
          ),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.add_a_photo_outlined,
                size: 22, color: AppColors.primary),
            SizedBox(height: 5),
            Text(
              '添加照片',
              style: TextStyle(fontSize: 11.5, color: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}

class _NoteModeSwitch extends StatelessWidget {
  const _NoteModeSwitch({required this.mode, required this.onChanged});

  final _NoteMode mode;
  final ValueChanged<_NoteMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: <Widget>[
          _item(_NoteMode.text, Icons.keyboard_alt_outlined, '文字输入'),
          _item(_NoteMode.voice, Icons.mic_none, '语音转文字'),
        ],
      ),
    );
  }

  Widget _item(_NoteMode value, IconData icon, String label) {
    final bool selected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 38,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            boxShadow: selected ? kCardShadow : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color:
                      selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 语音模式下的区域：未录音显示引导，已录音显示播放条。
class _VoiceNoteArea extends StatelessWidget {
  const _VoiceNoteArea({
    required this.relativePath,
    required this.duration,
    required this.waveform,
    required this.onRecord,
    required this.onDelete,
  });

  final String? relativePath;
  final Duration? duration;
  final List<double> waveform;
  final VoidCallback onRecord;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String? path = relativePath;

    if (path == null) {
      return GestureDetector(
        onTap: onRecord,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 26),
          decoration: BoxDecoration(
            color: AppColors.primarySoft.withOpacity(0.5),
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: AppColors.primary.withOpacity(0.25)),
          ),
          child: Column(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: Colors.white, size: 26),
              ),
              const SizedBox(height: 12),
              Text('点击开始录音',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                '边录边转文字，音频也会一起保存',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        VoicePlayerBar(
          relativePath: path,
          duration: duration,
          waveform: waveform,
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onRecord,
                icon: const Icon(Icons.refresh, size: 17),
                label: const Text('重新录制'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 17),
                label: const Text('删除录音'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                  side: BorderSide(color: AppColors.danger.withOpacity(0.35)),
                  minimumSize: const Size.fromHeight(42),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PhotoSourceSheet extends StatelessWidget {
  const _PhotoSourceSheet({required this.onPick});

  final ValueChanged<ImageSource> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 18),
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined,
                  color: AppColors.primary),
              title: const Text('拍照'),
              onTap: () => onPick(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('从相册选择'),
              onTap: () => onPick(ImageSource.gallery),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
