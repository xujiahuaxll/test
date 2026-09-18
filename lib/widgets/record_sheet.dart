import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

import '../services/media_store.dart';
import '../services/recorder_service.dart';
import '../services/speech_service.dart';
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

  /// 系统语音识别出的文字，识别不可用时为空串。
  final String transcript;
  final List<double> waveform;
}

/// 录音面板：真实录麦克风 + 实时振幅波形 + 系统语音转文字。
/// 语音识别与录音并行，识别不可用时自动降级为「只录音」。
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

enum _Stage { preparing, recording, paused, finishing, error }

class _RecordSheetState extends State<RecordSheet> {
  final RecorderService _recorder = RecorderService.instance;
  final SpeechService _speech = SpeechService.instance;

  _Stage _stage = _Stage.preparing;
  String _errorMessage = '';
  bool _permanentlyDenied = false;

  String? _relativePath;
  String? _absolutePath;

  Duration _elapsed = Duration.zero;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitudeSub;
  final List<double> _levels = <double>[];

  bool _speechAvailable = false;
  String _transcript = '';

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

    final ({String absolute, String relative}) file =
        await MediaStore.instance.newAudioFile();
    _relativePath = file.relative;
    _absolutePath = file.absolute;

    try {
      await _recorder.start(file.absolute);
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

    // 与录音并行做语音识别；设备不支持时只录音。
    final bool speechOk = await _speech.start(
      onText: (String text) {
        if (!mounted) return;
        setState(() => _transcript = text);
      },
    );
    if (!mounted) return;
    setState(() {
      _speechAvailable = speechOk;
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
      if (_speechAvailable) await _speech.stop();
      if (!mounted) return;
      setState(() => _stage = _Stage.paused);
    } else if (_stage == _Stage.paused) {
      await _recorder.resume();
      _startTimer();
      if (_speechAvailable) {
        await _speech.start(
          initial: _transcript,
          onText: (String text) {
            if (!mounted) return;
            setState(() => _transcript = text);
          },
        );
      }
      if (!mounted) return;
      setState(() => _stage = _Stage.recording);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _amplitudeSub?.cancel();
    await _speech.cancel();
    final String? path = _absolutePath;
    if (path != null) await _recorder.cancel(path);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _finish() async {
    setState(() => _stage = _Stage.finishing);
    _timer?.cancel();
    await _amplitudeSub?.cancel();

    final String transcript =
        _speechAvailable ? await _speech.stop() : '';
    final String? path = await _recorder.stop();

    if (!mounted) return;
    if (path == null || _relativePath == null) {
      setState(() {
        _stage = _Stage.error;
        _errorMessage = '录音保存失败，请重试';
      });
      return;
    }

    Navigator.of(context).pop(
      RecordResult(
        relativePath: _relativePath!,
        duration: _elapsed,
        transcript: transcript.isNotEmpty ? transcript : _transcript,
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
    final bool finishing = _stage == _Stage.finishing;
    final bool preparing = _stage == _Stage.preparing;

    return Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            if (!finishing && !preparing)
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
            if (!finishing && !preparing) const SizedBox(width: 8),
            Text(
              finishing
                  ? '正在保存录音…'
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
        _buildTranscriptArea(),
        const SizedBox(height: 22),
        if (finishing)
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

  Widget _buildTranscriptArea() {
    if (_stage == _Stage.preparing) return const SizedBox(height: 46);

    if (!_speechAvailable) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
        child: const Text(
          '本机的语音识别不可用，这次只保存录音，文字可以录完后手动补充',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
        ),
      );
    }

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 46, maxHeight: 120),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: SingleChildScrollView(
        reverse: true,
        child: Text(
          _transcript.isEmpty ? '正在识别，说话内容会实时出现在这里…' : _transcript,
          style: TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: _transcript.isEmpty
                ? AppColors.textTertiary
                : AppColors.textPrimary,
          ),
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
