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

/// 录音中的实时波形：直接画麦克风采集到的振幅序列，右侧为最新。
class LiveWaveform extends StatelessWidget {
  const LiveWaveform({
    super.key,
    required this.levels,
    this.color = AppColors.primary,
    this.barCount = 34,
  });

  final List<double> levels;
  final Color color;
  final int barCount;

  @override
  Widget build(BuildContext context) {
    final List<double> tail = levels.length <= barCount
        ? <double>[
            ...List<double>.filled(barCount - levels.length, 0.06),
            ...levels,
          ]
        : levels.sublist(levels.length - barCount);

    return WaveformBars(
      levels: tail,
      progress: 1,
      activeColor: color,
      barWidth: 3.5,
    );
  }
}
