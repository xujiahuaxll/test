import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/asr_service.dart';
import '../services/media_store.dart';
import '../services/recorder_service.dart';
import '../theme/app_theme.dart';
import 'waveform.dart';

/// 一次录音的产物。
class RecordResult {
  const RecordResult({
    required this.relativePath,
    required this.duration,
    required this.transcript,
    required this.waveform,
  });

  /// 相对应用目录的音频路径。
  final String relativePath;
  final Duration duration;

  /// 离线识别出的文字。没识别出来或用户跳过时为空串。
  final String transcript;
  final List<double> waveform;
}

/// 录音面板：录麦克风 + 实时振幅波形，停下来之后用本地模型转文字。
///
/// 转文字放在录完之后，不是边录边转。原因是系统的实时识别要独占麦克风，
/// 和录音抢，两边只能活一个；换成本地离线模型就没这个矛盾了，代价是文字
/// 要等录完才出来。
class RecordSheet extends StatefulWidget {
  const RecordSheet({super.key});

  /// 返回 null 表示用户取消或录音未成功。
  static Future<RecordResult?> show(BuildContext context) {
    return showModalBottomSheet<RecordResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const RecordSheet(),
    );
  }

  @override
  State<RecordSheet> createState() => _RecordSheetState();
}

enum _Stage { preparing, recording, paused, transcribing, error }

class _RecordSheetState extends State<RecordSheet> {
  final RecorderService _recorder = RecorderService.instance;

  _Stage _stage = _Stage.preparing;
  String _errorMessage = '';
  bool _permanentlyDenied = false;

  String? _relativePath;
  String? _absolutePath;
  RecordFormat _format = RecordFormat.wav;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _levels = <double>[];

  /// 本机能不能做离线识别：模型没打进包里，或录出来的不是 WAV，都不能。
  bool _canTranscribe = false;
  String _transcript = '';
  String _transcribeNote = '';

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _amplitudeSub?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (!await _recorder.hasPermission()) {
      final PermissionStatus status = await Permission.microphone.status;
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _permanentlyDenied = status.isPermanentlyDenied;
        _errorMessage = status.isPermanentlyDenied
            ? '麦克风权限已被拒绝，请到系统设置里重新允许'
            : '没有麦克风权限，无法录音';
      });
      return;
    }

    // 先定格式再分配文件名，后缀得和真实格式对上。
    _format = await _recorder.preferredFormat();
    final ({String absolute, String relative}) file =
        await MediaStore.instance.newAudioFile(extension: _format.extension);
    _relativePath = file.relative;
    _absolutePath = file.absolute;

    try {
      await _recorder.start(file.absolute, _format);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.error;
        _errorMessage = '录音启动失败：$e';
      });
      return;
    }

    _amplitudeSub = _recorder.amplitude().listen((Amplitude amplitude) {
      if (!mounted) return;
      setState(() => _levels.add(_normalize(amplitude.current)));
    });

    _startTimer();

    // 模型在不在是个纯本地的检查，顺手问一下，好在界面上提前说清楚
    // 这次到底有没有文字——别让人录完了才发现没有。
    final bool modelReady =
        _format.transcribable && await AsrService.instance.isAvailable();
    if (!mounted) return;
    setState(() {
      _canTranscribe = modelReady;
      _stage = _Stage.recording;
    });
  }

  /// record 给的是 dBFS（约 -60 ~ 0），映射成 0~1 的柱高。
  double _normalize(double db) {
    const double floor = 50;
    final double value = (db + floor) / floor;
    return value.clamp(0.06, 1.0);
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _togglePause() async {
    if (_stage == _Stage.recording) {
      await _recorder.pause();
      _timer?.cancel();
      if (!mounted) return;
      setState(() => _stage = _Stage.paused);
    } else if (_stage == _Stage.paused) {
      await _recorder.resume();
      _startTimer();
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _amplitudeSub?.cancel();
    final String? path = _absolutePath;
    if (path != null) await _recorder.cancel(path);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    setState(() {
      _stage = _Stage.transcribing;
      _transcribeNote = _canTranscribe ? '' : '这次只保存录音，文字可以稍后补';
    });
    _timer?.cancel();
    await _amplitudeSub?.cancel();

    final String? path = await _recorder.stop();
    if (!mounted) return;
    if (path == null || _relativePath == null) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage = '录音保存失败，请重试';
      });
      return;
    }

    if (_canTranscribe) {
      try {
        _transcript = await AsrService.instance.transcribeFile(path);
      } on AsrFailure catch (e) {
        // 转写失败不能连累录音：文字留空，回到编辑页还能点「重新识别」。
        _transcribeNote = e.message;
      } catch (e) {
        _transcribeNote = '转文字失败：$e';
      }
    }

    if (!mounted) return;
    _pop();
  }

  /// 把这次录音的结果交回给编辑页。
  ///
  /// 文字可能是空的——模型没带、格式不对、或者压根没识别出东西。
  /// 那也照样返回：录音本身已经存好了，文字在编辑页还能补、还能重试。
  void _pop() {
    Navigator.of(context).pop(
      RecordResult(
        relativePath: _relativePath!,
        duration: _elapsed,
        transcript: _transcript,
        waveform: List<double>.unmodifiable(_levels),
      ),
    );
  }

  String get _timeText {
    final String m = _elapsed.inMinutes.toString().padLeft(2, '0');
    final String s = (_elapsed.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
            const SizedBox(height: 22),
            if (_stage == _Stage.error) _buildError() else _buildRecorder(),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Column(
      children: <Widget>[
        const Icon(Icons.mic_off_outlined, size: 40, color: AppColors.danger),
        const SizedBox(height: 14),
        Text(
          _errorMessage,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  foregroundColor: AppColors.textSecondary,
                  side: const BorderSide(color: AppColors.divider),
                ),
                child: const Text('关闭'),
              ),
            ),
            if (_permanentlyDenied) ...<Widget>[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: openAppSettings,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('去设置'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildRecorder() {
    final bool transcribing = _stage == _Stage.transcribing;
    final bool preparing = _stage == _Stage.preparing;

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!transcribing && !preparing)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _stage == _Stage.recording
                      ? AppColors.danger
                      : AppColors.textTertiary,
                  shape: BoxShape.circle,
                ),
              ),
            if (!transcribing && !preparing) const SizedBox(width: 8),
            Text(
              transcribing
                  ? (_canTranscribe ? '正在转文字…' : '正在保存录音…')
                  : preparing
                      ? '准备中…'
                      : _stage == _Stage.recording
                          ? '正在录音'
                          : '已暂停',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          _timeText,
          style: const TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w300,
            color: AppColors.textPrimary,
            fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          height: 56,
          child: LiveWaveform(levels: _levels),
        ),
        const SizedBox(height: 16),
        _buildHintArea(),
        const SizedBox(height: 22),
        if (transcribing)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(
                strokeWidth: 2.4,
                color: AppColors.primary,
              ),
            ),
          )
        else
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _CircleAction(
                icon: Icons.close,
                label: '取消',
                background: AppColors.background,
                foreground: AppColors.textSecondary,
                onTap: preparing ? null : _cancel,
              ),
              _CircleAction(
                icon: _stage == _Stage.recording ? Icons.pause : Icons.mic,
                label: _stage == _Stage.recording ? '暂停' : '继续',
                size: 72,
                background: AppColors.danger,
                foreground: Colors.white,
                onTap: preparing ? null : _togglePause,
              ),
              _CircleAction(
                icon: Icons.check,
                label: '完成',
                background: AppColors.primarySoft,
                foreground: AppColors.primary,
                onTap: preparing ? null : _finish,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildHintArea() {
    if (_stage == _Stage.preparing) return const SizedBox(height: 46);

    final String text;
    if (_stage == _Stage.transcribing) {
      text = _transcribeNote.isNotEmpty
          ? _transcribeNote
          : '录音已经存好，正在用本机的离线模型识别，稍等一下';
    } else if (_canTranscribe) {
      text = '说完点「完成」，会自动转成文字，识别全程在本机进行，不联网';
    } else {
      text = '本机没有可用的离线语音模型，这次只保存录音，文字可以录完后手动补充';
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 46),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.size = 54,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Material(
          color: onTap == null ? AppColors.divider : background,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: foreground, size: size * 0.42),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}
