import 'package:flutter/material.dart';

import '../models/marker.dart';
import '../theme/app_theme.dart';
import 'waveform.dart';

/// 录音播放条（Demo）：点击播放只是把进度条动画跑一遍，不播真实音频。
class VoicePlayerBar extends StatefulWidget {
  const VoicePlayerBar({
    super.key,
    required this.voiceNote,
    this.seed = 21,
    this.compact = false,
  });

  final VoiceNote voiceNote;
  final int seed;
  final bool compact;

  @override
  State<VoicePlayerBar> createState() => _VoicePlayerBarState();
}

class _VoicePlayerBarState extends State<VoicePlayerBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.voiceNote.duration,
  )..addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        _controller.reset();
        setState(() {});
      }
    });

  late final List<double> _levels = buildWaveform(widget.seed);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      if (_controller.isAnimating) {
        _controller.stop();
      } else {
        _controller.forward();
      }
    });
  }

  String _remaining(double progress) {
    final int total = widget.voiceNote.duration.inSeconds;
    final int played = (total * progress).round();
    final int left = (total - played).clamp(0, total);
    return '${(left ~/ 60).toString().padLeft(2, '0')}:'
        '${(left % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: 14,
        vertical: widget.compact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.primarySoft.withOpacity(0.55),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          final bool playing = _controller.isAnimating;
          return Row(
            children: <Widget>[
              Material(
                color: AppColors.primary,
                shape: const CircleBorder(),
                child: InkWell(
                  onTap: _toggle,
                  customBorder: const CircleBorder(),
                  child: SizedBox(
                    width: widget.compact ? 36 : 42,
                    height: widget.compact ? 36 : 42,
                    child: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      color: Colors.white,
                      size: widget.compact ? 20 : 24,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: widget.compact ? 26 : 32,
                  child: WaveformBars(
                    levels: _levels,
                    progress: _controller.value,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _remaining(_controller.value),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
