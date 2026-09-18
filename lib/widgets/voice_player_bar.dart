import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:flutter/material.dart';

import '../models/location_mark.dart';
import '../services/media_store.dart';
import '../theme/app_theme.dart';
import 'waveform.dart';

/// 录音播放条：just_audio 播放应用目录里的真实音频文件。
class VoicePlayerBar extends StatefulWidget {
  const VoicePlayerBar({
    super.key,
    required this.relativePath,
    this.duration,
    this.waveform = const <double>[],
    this.compact = false,
  });

  /// 数据库里存的相对路径。
  final String relativePath;
  final Duration? duration;

  /// 录音时采集到的真实振幅包络；为空时退回一条示意波形。
  final List<double> waveform;
  final bool compact;

  @override
  State<VoicePlayerBar> createState() => _VoicePlayerBarState();
}

class _VoicePlayerBarState extends State<VoicePlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  late final List<double> _levels = widget.waveform.isNotEmpty
      ? widget.waveform
      : buildWaveform(widget.relativePath.hashCode);

  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await _player.setFilePath(MediaStore.instance.absolute(widget.relativePath));
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '录音文件读取失败');
    }
  }

  @override
  void didUpdateWidget(covariant VoicePlayerBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.relativePath != widget.relativePath) {
      _ready = false;
      _error = null;
      _load();
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (!_ready) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      if (_player.processingState == ProcessingState.completed) {
        await _player.seek(Duration.zero);
      }
      await _player.play();
    }
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
      child: _error != null
          ? Row(
              children: <Widget>[
                const Icon(Icons.error_outline,
                    size: 18, color: AppColors.danger),
                const SizedBox(width: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
            )
          : StreamBuilder<Duration>(
              stream: _player.positionStream,
              builder: (BuildContext context,
                  AsyncSnapshot<Duration> positionSnapshot) {
                final Duration total =
                    _player.duration ?? widget.duration ?? Duration.zero;
                final Duration position =
                    positionSnapshot.data ?? Duration.zero;
                final double progress = total.inMilliseconds == 0
                    ? 0
                    : (position.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0);
                final Duration left = total - position;

                return Row(
                  children: <Widget>[
                    StreamBuilder<PlayerState>(
                      stream: _player.playerStateStream,
                      builder: (BuildContext context,
                          AsyncSnapshot<PlayerState> stateSnapshot) {
                        final bool playing =
                            stateSnapshot.data?.playing ?? false;
                        final bool completed = stateSnapshot.data?.processingState ==
                            ProcessingState.completed;
                        return Material(
                          color: AppColors.primary,
                          shape: const CircleBorder(),
                          child: InkWell(
                            onTap: _toggle,
                            customBorder: const CircleBorder(),
                            child: SizedBox(
                              width: widget.compact ? 36 : 42,
                              height: widget.compact ? 36 : 42,
                              child: Icon(
                                playing && !completed
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                                size: widget.compact ? 20 : 24,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (TapDownDetails details) {
                          final RenderBox box =
                              context.findRenderObject()! as RenderBox;
                          final double ratio = (details.localPosition.dx /
                                  box.size.width)
                              .clamp(0.0, 1.0);
                          _player.seek(total * ratio);
                        },
                        child: SizedBox(
                          height: widget.compact ? 26 : 32,
                          child: WaveformBars(
                            levels: _levels,
                            progress: progress,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      LocationMark.formatDuration(
                        left.isNegative ? Duration.zero : left,
                      ),
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
