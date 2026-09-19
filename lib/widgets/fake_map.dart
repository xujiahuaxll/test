import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Demo 用的「地图」：纯 CustomPaint 画出街区与路网，
/// 正式开发时整块替换为高德 / 腾讯 / Google 地图组件即可。
class FakeMap extends StatelessWidget {
  const FakeMap({
    super.key,
    this.seed = 7,
    this.showPin = true,
    this.pinAlignment = Alignment.center,
    this.dimmed = false,
  });

  final int seed;
  final bool showPin;
  final Alignment pinAlignment;

  /// 顶部有浮层内容时压暗一点，保证文字可读。
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        CustomPaint(painter: _FakeMapPainter(seed)),
        if (dimmed)
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.black.withValues(alpha: 0.02),
                  Colors.black.withValues(alpha: 0.16),
                ],
              ),
            ),
          ),
        if (showPin)
          Align(
            alignment: pinAlignment,
            child: const _MapPin(),
          ),
      ],
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AppColors.primaryDark.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.place, color: Colors.white, size: 20),
        ),
        const SizedBox(height: 2),
        Container(
          width: 10,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ],
    );
  }
}

class _FakeMapPainter extends CustomPainter {
  _FakeMapPainter(this.seed);

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final Random random = Random(seed);
    final Rect rect = Offset.zero & size;

    // 底色
    canvas.drawRect(rect, Paint()..color = const Color(0xFFEDF2EE));

    // 绿地
    final Paint parkPaint = Paint()..color = const Color(0xFFDCEBDE);
    for (int i = 0; i < 3; i++) {
      final double w = size.width * (0.18 + random.nextDouble() * 0.22);
      final double h = size.height * (0.16 + random.nextDouble() * 0.26);
      final double x = random.nextDouble() * (size.width - w);
      final double y = random.nextDouble() * (size.height - h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(10),
        ),
        parkPaint,
      );
    }

    // 河道
    final Path river = Path()
      ..moveTo(-10, size.height * 0.78)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.62,
        size.width * 0.62,
        size.height * 0.84,
      )
      ..quadraticBezierTo(
        size.width * 0.82,
        size.height * 0.98,
        size.width + 10,
        size.height * 0.72,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFCBE3F0)
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.09
        ..strokeCap = StrokeCap.round,
    );

    // 街区
    final Paint blockPaint = Paint()..color = const Color(0xFFE3E9E4);
    for (int i = 0; i < 9; i++) {
      final double w = size.width * (0.1 + random.nextDouble() * 0.16);
      final double h = size.height * (0.08 + random.nextDouble() * 0.2);
      final double x = random.nextDouble() * (size.width - w);
      final double y = random.nextDouble() * (size.height - h);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          const Radius.circular(6),
        ),
        blockPaint,
      );
    }

    // 主干道 + 支路
    final Paint mainRoad = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.055;
    final Paint subRoad = Paint()
      ..color = Colors.white.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.025;

    canvas.drawLine(
      Offset(0, size.height * 0.34),
      Offset(size.width, size.height * 0.28),
      mainRoad,
    );
    canvas.drawLine(
      Offset(size.width * 0.58, 0),
      Offset(size.width * 0.47, size.height),
      mainRoad,
    );
    canvas.drawLine(
      Offset(0, size.height * 0.62),
      Offset(size.width, size.height * 0.58),
      subRoad,
    );
    canvas.drawLine(
      Offset(size.width * 0.2, 0),
      Offset(size.width * 0.26, size.height),
      subRoad,
    );
    canvas.drawLine(
      Offset(size.width * 0.82, 0),
      Offset(size.width * 0.78, size.height),
      subRoad,
    );
  }

  @override
  bool shouldRepaint(covariant _FakeMapPainter oldDelegate) =>
      oldDelegate.seed != seed;
}
