import 'package:flutter/material.dart';

import '../data/demo_data.dart';
import '../models/marker.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/fake_map.dart';
import '../widgets/record_sheet.dart';
import '../widgets/voice_player_bar.dart';

/// 添加标记页（UI Demo）。
/// 进入即模拟「自动定位」：先转圈，再显示地址与经纬度。
class AddMarkerPage extends StatefulWidget {
  const AddMarkerPage({super.key});

  @override
  State<AddMarkerPage> createState() => _AddMarkerPageState();
}

enum _LocateState { locating, located }

enum _NoteMode { text, voice }

class _AddMarkerPageState extends State<AddMarkerPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  _LocateState _locateState = _LocateState.locating;
  _NoteMode _noteMode = _NoteMode.text;
  final Set<String> _selectedTags = <String>{'风景'};
  final List<DemoPhoto> _photos = <DemoPhoto>[];
  VoiceNote? _voiceNote;

  @override
  void initState() {
    super.initState();
    _locate();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  /// Demo：用延时模拟一次定位请求。
  Future<void> _locate() async {
    setState(() => _locateState = _LocateState.locating);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _locateState = _LocateState.located);
  }

  Future<void> _record() async {
    final VoiceNote? note = await RecordSheet.show(context);
    if (note == null || !mounted) return;
    setState(() {
      _voiceNote = note;
      // 转写结果直接落到备注文本里，可继续手动编辑。
      if (_noteController.text.trim().isEmpty) {
        _noteController.text = note.transcript;
      } else {
        _noteController.text = '${_noteController.text}\n${note.transcript}';
      }
    });
  }

  void _addPhoto() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => _PhotoSourceSheet(
        onPick: () {
          Navigator.of(sheetContext).pop();
          setState(() {
            _photos.add(
              DemoData.photoPool[_photos.length % DemoData.photoPool.length],
            );
          });
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('新建标记'),
        actions: <Widget>[
          TextButton(
            onPressed: () => _showSaved(context),
            child: const Text(
              '保存',
              style: TextStyle(
                color: AppColors.primary,
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
          _LocationCard(state: _locateState, onRetry: _locate),
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
            onPressed: () => _showSaved(context),
            child: const Text('保存标记'),
          ),
          const SizedBox(height: 10),
          Center(
            child: Text(
              '当前为界面演示，数据不会真正保存',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textTertiary,
                  ),
            ),
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
              for (final String tag in DemoData.allTags)
                _SelectableTag(
                  tag: tag,
                  selected: _selectedTags.contains(tag),
                  onTap: () => setState(() {
                    if (!_selectedTags.remove(tag)) _selectedTags.add(tag);
                  }),
                ),
              _AddTagChip(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('自定义标签（Demo 未实现）')),
                ),
              ),
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
              '${_photos.length}/9',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 86,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _photos.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _AddPhotoButton(onTap: _addPhoto);
                }
                final int photoIndex = index - 1;
                return Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    PhotoThumb(photo: _photos[photoIndex], size: 86),
                    Positioned(
                      right: -6,
                      top: -6,
                      child: GestureDetector(
                        onTap: () =>
                            setState(() => _photos.removeAt(photoIndex)),
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
          if (_noteMode == _NoteMode.text)
            TextField(
              controller: _noteController,
              maxLines: 5,
              minLines: 4,
              decoration: const InputDecoration(
                hintText: '写点什么，比如营业时间、停车位置、下次再来要注意的事…',
              ),
            )
          else
            _VoiceNoteArea(
              voiceNote: _voiceNote,
              onRecord: _record,
              onDelete: () => setState(() => _voiceNote = null),
            ),
          if (_noteMode == _NoteMode.text) ...<Widget>[
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
                  onPressed: () {
                    setState(() => _noteMode = _NoteMode.voice);
                    _record();
                  },
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
          ],
          if (_noteMode == _NoteMode.voice && _voiceNote != null) ...<Widget>[
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
                hintText: '识别结果会显示在这里',
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showSaved(BuildContext context) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('保存成功（Demo：未写入任何数据）')),
      );
    Navigator.of(context).maybePop();
  }
}

/// 顶部定位卡片：地图 + 定位状态 + 地址 / 经纬度。
class _LocationCard extends StatelessWidget {
  const _LocationCard({required this.state, required this.onRetry});

  final _LocateState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final bool locating = state == _LocateState.locating;

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
                const FakeMap(seed: 12, dimmed: true),
                Positioned(
                  left: 12,
                  top: 12,
                  child: _MapChip(
                    icon: locating ? Icons.gps_not_fixed : Icons.gps_fixed,
                    label: locating ? '定位中' : '已定位 · 精度 8 米',
                    highlight: !locating,
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
            child: locating
                ? Row(
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
                  )
                : Column(
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
                              '浙江省杭州市西湖区北山街 78 号',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: <Widget>[
                          Text(
                            '30.259924, 120.146515',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppColors.textTertiary),
                          ),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                  content: Text('手动选点（Demo 未实现）')),
                            ),
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
      child: const DottedBorderBox(
        size: 86,
        child: Column(
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

/// 虚线感的添加框（用浅色描边近似，避免额外依赖）。
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.size, required this.child});

  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.35),
          width: 1.2,
        ),
      ),
      child: child,
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
          _item(context, _NoteMode.text, Icons.keyboard_alt_outlined, '文字输入'),
          _item(context, _NoteMode.voice, Icons.mic_none, '语音转文字'),
        ],
      ),
    );
  }

  Widget _item(
    BuildContext context,
    _NoteMode value,
    IconData icon,
    String label,
  ) {
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
                color:
                    selected ? AppColors.primary : AppColors.textSecondary,
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
    required this.voiceNote,
    required this.onRecord,
    required this.onDelete,
  });

  final VoiceNote? voiceNote;
  final VoidCallback onRecord;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    if (voiceNote == null) {
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
              Text(
                '点击开始录音',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              Text(
                '录完自动转成文字，音频也会一起保存',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        VoicePlayerBar(voiceNote: voiceNote!),
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

  final VoidCallback onPick;

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
              onTap: onPick,
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined,
                  color: AppColors.primary),
              title: const Text('从相册选择'),
              onTap: onPick,
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
