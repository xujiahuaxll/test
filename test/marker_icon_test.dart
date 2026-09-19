import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/utils/marker_icon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('封面缩略图的裁剪框', () {
    test('竖图取中间的正方形，不压扁', () {
      final Rect rect = MarkerIcon.coverRect(600, 1000);
      expect(rect.width, rect.height);
      expect(rect.width, 600);
      // 上下各切掉 200
      expect(rect.top, 200);
    });

    test('横图同理，左右各切一半', () {
      final Rect rect = MarkerIcon.coverRect(1000, 400);
      expect(rect.width, 400);
      expect(rect.left, 300);
      expect(rect.top, 0);
    });

    test('本来就是方的就整张用上', () {
      expect(
        MarkerIcon.coverRect(500, 500),
        const Rect.fromLTWH(0, 0, 500, 500),
      );
    });
  });

  group('画图标', () {
    test('没有封面时也画得出一张 PNG', () async {
      final Uint8List bytes = await MarkerIcon.render(
        color: const Color(0xFF2F9E7E),
        pixelRatio: 2,
      );
      expect(bytes, isNotEmpty);
      // PNG 魔数，确认拿到的确实是图片而不是一堆零
      expect(bytes.sublist(0, 4), <int>[0x89, 0x50, 0x4E, 0x47]);
    });

    test('按像素密度出图，尺寸跟着放大', () async {
      final ui.Image low = await decode(
        await MarkerIcon.render(color: const Color(0xFF2F9E7E), pixelRatio: 1),
      );
      final ui.Image high = await decode(
        await MarkerIcon.render(color: const Color(0xFF2F9E7E), pixelRatio: 3),
      );
      expect(low.width, MarkerIcon.width.round());
      expect(high.width, (MarkerIcon.width * 3).round());
      low.dispose();
      high.dispose();
    });

    test('选中态和未选中态画出来不一样，否则地图上分不出点了哪个', () async {
      final Uint8List normal = await MarkerIcon.render(
        color: const Color(0xFFE2703A),
        pixelRatio: 2,
      );
      final Uint8List selected = await MarkerIcon.render(
        color: const Color(0xFFE2703A),
        selected: true,
        pixelRatio: 2,
      );
      expect(normal, isNot(selected));
    });

    test('读不到的图片路径返回 null，退回没有缩略图的图钉', () async {
      expect(await MarkerIcon.loadThumb('/nowhere/missing.jpg'), isNull);
    });
  });
}

Future<ui.Image> decode(Uint8List bytes) async {
  final ui.Codec codec = await ui.instantiateImageCodec(bytes);
  final ui.FrameInfo frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
