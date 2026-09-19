import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 画地图上的标记图标。
///
/// 高德的 Marker 只认一张位图，所以形状、封面缩略图、选中效果全都得自己
/// 画到一张图上。几十个点挤在一起时，光靠默认的红气球分不出谁是谁——
/// 顶上那张封面缩略图就是用来认人的，选中的那个则整体放大加白边。
class MarkerIcon {
  const MarkerIcon._();

  /// 图标的逻辑尺寸。底边中点对准坐标（Marker 默认锚点 0.5/1.0）。
  static const double width = 58;
  static const double height = 88;

  /// 悬浮缩略图的边长。
  static const double thumbSize = 30;
  static const double thumbSizeSelected = 38;

  /// 图钉头的半径。
  static const double headRadius = 12;
  static const double headRadiusSelected = 15;

  /// 画一个标记图标，返回 PNG 字节，直接喂给 BitmapDescriptor.fromBytes。
  ///
  /// [photo] 为空时只画图钉，不画缩略图——留一张空白的占位框比没有还难看。
  static Future<Uint8List> render({
    required Color color,
    ui.Image? photo,
    bool selected = false,
    double pixelRatio = 3,
  }) async {
    final double scale = pixelRatio.clamp(1.0, 4.0);
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.scale(scale);

    _paint(canvas, color: color, photo: photo, selected: selected);

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      (width * scale).round(),
      (height * scale).round(),
    );
    picture.dispose();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  static void _paint(
    Canvas canvas, {
    required Color color,
    required ui.Image? photo,
    required bool selected,
  }) {
    const double cx = width / 2;
    const double tipY = height - 4;
    final double radius = selected ? headRadiusSelected : headRadius;
    final double headY = tipY - radius * 2.6;

    // 地面上的投影，让图钉看着是立着的
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(cx, tipY - 1), width: 16, height: 5),
      Paint()..color = const Color(0x22000000),
    );

    // 选中的那个套一圈光晕，几十个点里一眼能找到
    if (selected) {
      canvas.drawCircle(
        Offset(cx, headY),
        radius + 6,
        Paint()..color = color.withValues(alpha: 0.22),
      );
    }

    // 图钉：圆头 + 下面收成一个尖
    final Path pin = Path()
      ..addOval(Rect.fromCircle(center: Offset(cx, headY), radius: radius))
      ..moveTo(cx - radius * 0.62, headY + radius * 0.78)
      ..lineTo(cx + radius * 0.62, headY + radius * 0.78)
      ..lineTo(cx, tipY)
      ..close();
    canvas.drawPath(pin, Paint()..color = color);
    if (selected) {
      canvas.drawPath(
        pin,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..color = const Color(0xFFFFFFFF),
      );
    }

    // 头里的白点，纯粹让图钉看着有个「眼」
    canvas.drawCircle(
      Offset(cx, headY),
      radius * 0.34,
      Paint()..color = const Color(0xFFFFFFFF),
    );

    if (photo == null) return;

    // 悬浮在图钉上方的封面缩略图
    final double side = selected ? thumbSizeSelected : thumbSize;
    final Rect card = Rect.fromCenter(
      center: Offset(cx, 2 + side / 2),
      width: side,
      height: side,
    );
    final RRect rounded = RRect.fromRectAndRadius(
      card,
      const Radius.circular(8),
    );

    canvas.drawRRect(
      rounded.shift(const Offset(0, 1.5)),
      Paint()
        ..color = const Color(0x33000000)
        ..maskFilter = const ui.MaskFilter.blur(BlurStyle.normal, 2),
    );
    canvas.drawRRect(rounded, Paint()..color = const Color(0xFFFFFFFF));

    canvas.save();
    canvas.clipRRect(rounded.deflate(2));
    canvas.drawImageRect(
      photo,
      coverRect(photo.width.toDouble(), photo.height.toDouble()),
      card.deflate(2),
      Paint()..filterQuality = FilterQuality.medium,
    );
    canvas.restore();

    // 选中时缩略图也镶一道主色边，和图钉呼应
    canvas.drawRRect(
      rounded,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = selected ? 2.5 : 1.5
        ..color = selected ? color : const Color(0xFFFFFFFF),
    );
  }

  /// 方形取景框里的居中裁剪区（等价于 BoxFit.cover）。
  ///
  /// 不裁的话竖图会被压扁成一张脸谱，缩略图本来就小，变形就更认不出了。
  static Rect coverRect(double imageWidth, double imageHeight) {
    final double side = math.min(imageWidth, imageHeight);
    return Rect.fromLTWH(
      (imageWidth - side) / 2,
      (imageHeight - side) / 2,
      side,
      side,
    );
  }

  /// 读一张本地图片并解码成缩略图尺寸。
  ///
  /// 解码时就按目标宽度缩小：地图上几十个点，按原图解码是几十兆内存。
  static Future<ui.Image?> loadThumb(String path, {int targetWidth = 140}) async {
    try {
      final File file = File(path);
      if (!await file.exists()) return null;
      final Uint8List bytes = await file.readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: targetWidth,
      );
      final ui.FrameInfo frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      // 图片被删了或者格式不认，退回到没有缩略图的图钉
      return null;
    }
  }
}
