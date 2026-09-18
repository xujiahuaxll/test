import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../models/marker.dart';
import '../theme/app_theme.dart';
import 'waveform.dart';

/// 录音面板（Demo）：计时与波形都是动画模拟，
/// 停止后走一段假的「转文字中」再返回一条 VoiceNote。
class RecordSheet extends StatefulWidget {
  const RecordSheet({super.key});

  /// 返回 null 表示用户取消。
  static Future<VoiceNote?> show(BuildContext context) {
    return showModalBottomSheet<VoiceNote>(
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

enum _RecordStage { recording, paused, transcribing }

class _RecordSheetState extends State<RecordSheet> {
  static const String _demoTranscript =
      '门口右手边有一条石板路，往里走两百米就是观景平台，晚上七点后灯会关掉，记得带手电。';

  _RecordStage _stage = _RecordStage.recording;
  int _seconds = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _seconds++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _timeText {
    final String m = (_seconds ~/ 60).toString().padLeft(2, '0');
    final String s = (_seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _togglePause() {
    setState(() {
      if (_stage == _RecordStage.recording) {
        _stage = _RecordStage.paused;
        _timer?.cancel();
      } else {
        _stage = _RecordStage.recording;
        _startTimer();
      }
    });
  }

  Future<void> _finish() async {
    _timer?.cancel();
    setState(() => _stage = _RecordStage.transcribing);

    // Demo：假装在做语音转文字
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    Navigator.of(context).pop(
      VoiceNote(
        duration: Duration(seconds: _seconds == 0 ? 8 : _seconds),
        transcript: _demoTranscript,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool transcribing = _stage == _RecordStage.transcribing;

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
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (!transcribing)
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _stage == _RecordStage.recording
                          ? AppColors.danger
                          : AppColors.textTertiary,
                      shape: BoxShape.circle,
                    ),
                  ),
                if (!transcribing) const SizedBox(width: 8),
                Text(
                  transcribing
                      ? '正在转换为文字…'
                      : _stage == _RecordStage.recording
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
            const SizedBox(height: 22),
            SizedBox(
              height: 56,
              child: transcribing
                  ? const _TranscribingIndicator()
                  : LiveWaveform(
                      running: _stage == _RecordStage.recording,
                      color: AppColors.primary,
                    ),
            ),
            const SizedBox(height: 26),
            if (transcribing)
              const Text(
                '识别完成后会自动填入备注，可再手动修改',
                style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
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
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  _CircleAction(
                    icon: _stage == _RecordStage.recording
                        ? Icons.pause
                        : Icons.mic,
                    label: _stage == _RecordStage.recording ? '暂停' : '继续',
                    size: 72,
                    background: AppColors.danger,
                    foreground: Colors.white,
                    onTap: _togglePause,
                  ),
                  _CircleAction(
                    icon: Icons.check,
                    label: '完成',
                    background: AppColors.primarySoft,
                    foreground: AppColors.primary,
                    onTap: _finish,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _TranscribingIndicator extends StatelessWidget {
  const _TranscribingIndicator();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const <Widget>[
        SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(
            strokeWidth: 2.4,
            color: AppColors.primary,
          ),
        ),
      ],
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
          color: background,
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
