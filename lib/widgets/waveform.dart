import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 生成一组稳定的波形高度（0.15 ~ 1.0），同一 seed 每次结果一致。
List<double> buildWaveform(int seed, {int count = 42}) {
  final Random random = Random(seed);
  return List<double>.generate(count, (int i) {
    final double base = 0.35 + random.nextDouble() * 0.65;
    // 加一点周期性起伏，看起来更像真实语音。
    final double wave = 0.22 * sin(i / 3.2);
    return (base + wave).clamp(0.15, 1.0);
  });
}

/// 静态波形条：progress 之前的部分高亮，用于播放进度示意。
class WaveformBars extends StatelessWidget {
  const WaveformBars({
    super.key,
    required this.levels,
    this.progress = 0,
    this.activeColor = AppColors.primary,
    this.inactiveColor = const Color(0xFFC9D6D1),
    this.barWidth = 3,
    this.spacing = 3,
  });

  final List<double> levels;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final double barWidth;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int maxBars =
            ((constraints.maxWidth + spacing) / (barWidth + spacing)).floor();
        final int count = min(levels.length, max(maxBars, 1));
        final int playedCount = (count * progress).round();

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: List<Widget>.generate(count, (int i) {
            final double h = constraints.maxHeight * levels[i];
            return Container(
              width: barWidth,
              height: h.clamp(3.0, constraints.maxHeight),
              decoration: BoxDecoration(
                color: i < playedCount ? activeColor : inactiveColor,
                borderRadius: BorderRadius.circular(barWidth),
              ),
            );
          }),
        );
      },
    );
  }
}

/// 录音中的动态波形（纯视觉动画，不接真实音频输入）。
class LiveWaveform extends StatefulWidget {
  const LiveWaveform({
    super.key,
    this.color = AppColors.primary,
    this.barCount = 34,
    this.running = true,
  });

  final Color color;
  final int barCount;
  final bool running;

  @override
  State<LiveWaveform> createState() => _LiveWaveformState();
}

class _LiveWaveformState extends State<LiveWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  late final List<double> _phases = List<double>.generate(
    widget.barCount,
    (int i) => Random(i * 31 + 7).nextDouble() * pi * 2,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        final double t = _controller.value * pi * 2;
        final List<double> levels = List<double>.generate(
          widget.barCount,
          (int i) {
            if (!widget.running) return 0.12;
            return (0.55 + 0.45 * sin(t + _phases[i])).clamp(0.12, 1.0);
          },
        );
        return WaveformBars(
          levels: levels,
          progress: 1,
          activeColor: widget.color,
          barWidth: 3.5,
        );
      },
    );
  }
}
