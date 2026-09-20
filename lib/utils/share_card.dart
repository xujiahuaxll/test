import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:qr/qr.dart';

import '../models/location_mark.dart';
import '../services/media_store.dart';
import 'coordinate.dart';
import 'marker_icon.dart';

/// 分享链接。
///
/// 用高德官方的 uri.amap.com：对方手机上装了高德就直接唤起 App 定位到这个
/// 点，没装就在网页版地图上显示。不需要对方也装这个 App——这是用户提的硬
/// 要求。
class ShareLink {
  const ShareLink._();

  /// 拼一条指向某个坐标的高德地图链接。
  ///
  /// 库里存的是 WGS-84，高德认的是 GCJ-02，差出去能有好几百米，所以必须先
  /// 转一道，并且用 `coordinate=gaode` 明确告诉对面这是哪套坐标。
  static String amapMarker({
    required double latitude,
    required double longitude,
    required String name,
  }) {
    final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(
      latitude,
      longitude,
    );
    final String title = name.trim().isEmpty ? '我标记的位置' : name.trim();
    return Uri(
      scheme: 'https',
      host: 'uri.amap.com',
      path: '/marker',
      queryParameters: <String, String>{
        'position': '${gcj.longitude.toStringAsFixed(6)},'
            '${gcj.latitude.toStringAsFixed(6)}',
        'name': title,
        'coordinate': 'gaode',
        'callnative': '1',
        'src': 'caidian',
      },
    ).toString();
  }

  /// 分享时一起带上的文字。
  ///
  /// 微信会把它丢掉（它的分享接收界面只取图片），但发短信、发邮件、发到
  /// Telegram 时这段文字是有用的，所以照样带上。
  static String caption(LocationMark mark) {
    final StringBuffer buffer = StringBuffer('📍 ${mark.name}');
    final String? address = mark.address;
    if (address != null && address.trim().isNotEmpty) {
      buffer.write('\n${address.trim()}');
    }
    buffer.write('\n${amapMarker(
      latitude: mark.latitude,
      longitude: mark.longitude,
      name: mark.name,
    )}');
    return buffer.toString();
  }
}

/// 画一张分享用的图片卡片。
///
/// 为什么要画成图片、还要把链接做成二维码：微信的分享接收界面只收图片，
/// 同一条 ACTION_SEND 里的文字会被直接丢掉，所以「又带图片又带链接」
/// 在微信里只有一条路——把链接画进图里，对方长按识别二维码。
/// 另一条路是接微信开放平台 SDK 发网页卡片，那要 AppID、应用审核、企业
/// 资质和一个真实网页，对一个自用 App 来说不划算。
class ShareCard {
  const ShareCard._();

  /// 卡片的逻辑尺寸。竖图，比例接近手机屏，微信里缩略图不会被裁得太狠。
  static const double width = 750;
  static const double coverHeight = 460;
  static const double padding = 44;
  static const double qrSize = 200;

  static const Color _ink = Color(0xFF1A1C1E);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _line = Color(0xFFE6E8EB);
  static const Color _paper = Color(0xFFFFFFFF);
  static const Color _accent = Color(0xFF2F6BFF);

  /// 画出卡片，返回 PNG 字节。
  static Future<Uint8List> render(LocationMark mark) async {
    final ui.Image? cover = mark.photoPaths.isEmpty
        ? null
        : await MarkerIcon.loadThumb(
            MediaStore.instance.absolute(mark.photoPaths.first),
            targetWidth: width.round(),
          );

    final String link = ShareLink.amapMarker(
      latitude: mark.latitude,
      longitude: mark.longitude,
      name: mark.name,
    );

    // 先把所有文字排好版，这样才知道卡片总共多高。
    final TextPainter title = _text(mark.name, size: 42, weight: FontWeight.w700);
    final TextPainter? address = _optional(
      mark.address,
      size: 26,
      color: _muted,
      maxLines: 2,
    );
    final TextPainter? note = _optional(
      mark.note,
      size: 27,
      color: _ink,
      maxLines: 4,
    );
    final TextPainter coordinate = _text(
      mark.coordinateText,
      size: 22,
      color: _muted,
    );

    final List<TextPainter> tags = <TextPainter>[
      for (final String tag in mark.tags)
        _text(tag, size: 23, color: _accent, weight: FontWeight.w600),
    ];

    double bodyHeight = padding;
    bodyHeight += title.height + 16;
    if (tags.isNotEmpty) bodyHeight += 44;
    if (address != null) bodyHeight += address.height + 10;
    bodyHeight += coordinate.height + 24;
    if (note != null) bodyHeight += note.height + 26;
    // 分隔线 + 底部二维码那一栏
    bodyHeight += 1 + 32 + qrSize + padding;

    final double totalHeight = (cover == null ? 0 : coverHeight) + bodyHeight;

    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width, totalHeight),
      Paint()..color = _paper,
    );

    double y = 0;
    if (cover != null) {
      const Rect dst = Rect.fromLTWH(0, 0, width, coverHeight);
      canvas.drawImageRect(
        cover,
        coverSrcRect(
          cover.width.toDouble(),
          cover.height.toDouble(),
          width,
          coverHeight,
        ),
        dst,
        Paint()..filterQuality = FilterQuality.high,
      );
      // 底部压一层渐变，让压在上面的「踩点」两个字读得清
      const Rect scrim = Rect.fromLTWH(0, coverHeight - 140, width, 140);
      canvas.drawRect(
        scrim,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[Color(0x00000000), Color(0x66000000)],
          ).createShader(scrim),
      );
      _text('踩点 · 我标记的地方', size: 24, color: const Color(0xFFFFFFFF))
          .paint(canvas, const Offset(padding, coverHeight - 54));
      y = coverHeight;
      cover.dispose();
    }

    y += padding;
    title.paint(canvas, Offset(padding, y));
    y += title.height + 16;

    if (tags.isNotEmpty) {
      double x = padding;
      for (final TextPainter tag in tags) {
        final double pillWidth = tag.width + 28;
        if (x + pillWidth > width - padding) break;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, y, pillWidth, 36),
            const Radius.circular(18),
          ),
          Paint()..color = _accent.withValues(alpha: 0.10),
        );
        tag.paint(canvas, Offset(x + 14, y + (36 - tag.height) / 2));
        x += pillWidth + 10;
      }
      y += 44;
    }

    if (address != null) {
      address.paint(canvas, Offset(padding, y));
      y += address.height + 10;
    }
    coordinate.paint(canvas, Offset(padding, y));
    y += coordinate.height + 24;

    if (note != null) {
      note.paint(canvas, Offset(padding, y));
      y += note.height + 26;
    }

    canvas.drawRect(
      Rect.fromLTWH(padding, y, width - padding * 2, 1),
      Paint()..color = _line,
    );
    y += 1 + 32;

    // 二维码靠右，左边留给说明文字
    final double qrLeft = width - padding - qrSize;
    _drawQr(canvas, link, Rect.fromLTWH(qrLeft, y, qrSize, qrSize));

    _text(
      '长按识别二维码',
      size: 28,
      weight: FontWeight.w600,
    ).paint(canvas, Offset(padding, y + 24));
    _text(
      '用高德地图打开这个位置，\n不用装「踩点」也能看。',
      size: 23,
      color: _muted,
      maxWidth: qrLeft - padding - 20,
      maxLines: 3,
    ).paint(canvas, Offset(padding, y + 68));

    final ui.Picture picture = recorder.endRecording();
    final ui.Image image = await picture.toImage(
      width.round(),
      totalHeight.round(),
    );
    picture.dispose();
    final ByteData? data =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  }

  /// 把二维码画进 [box]。
  ///
  /// 四周要留「静区」（quiet zone），不留的话紧贴着别的内容，
  /// 很多扫码器会识别不出来。
  static void _drawQr(Canvas canvas, String data, Rect box) {
    final QrImage qr = QrImage(
      QrCode.fromData(
        data: data,
        // M 档：能容忍约 15% 的破损。链接不长，用不着更高的冗余，
        // 档位越高模块越密，印在小图上反而更难扫。
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(box.inflate(10), const Radius.circular(12)),
      Paint()..color = _paper,
    );

    const int quiet = 2;
    final int modules = qr.moduleCount + quiet * 2;
    final double unit = box.width / modules;
    final Paint dark = Paint()..color = _ink;

    for (int row = 0; row < qr.moduleCount; row++) {
      for (int col = 0; col < qr.moduleCount; col++) {
        if (!qr.isDark(row, col)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            box.left + (col + quiet) * unit,
            box.top + (row + quiet) * unit,
            // 多画半个像素，避免相邻方块之间出现发丝缝
            unit + 0.5,
            unit + 0.5,
          ),
          dark,
        );
      }
    }
  }

  /// 按 BoxFit.cover 的方式算源图裁剪区。
  ///
  /// 不裁就会把竖着拍的照片压扁。这里单独拎出来是因为它纯粹是算术，
  /// 不碰画布，可以直接单测。
  static Rect coverSrcRect(
    double imageWidth,
    double imageHeight,
    double boxWidth,
    double boxHeight,
  ) {
    if (imageWidth <= 0 || imageHeight <= 0 || boxHeight <= 0) {
      return Rect.fromLTWH(0, 0, imageWidth, imageHeight);
    }
    final double want = boxWidth / boxHeight;
    final double have = imageWidth / imageHeight;
    if (have > want) {
      // 源图更宽，左右各切掉一点
      final double keep = imageHeight * want;
      return Rect.fromLTWH((imageWidth - keep) / 2, 0, keep, imageHeight);
    }
    // 源图更高，上下各切掉一点
    final double keep = imageWidth / want;
    return Rect.fromLTWH(0, (imageHeight - keep) / 2, imageWidth, keep);
  }

  static TextPainter _text(
    String text, {
    required double size,
    Color color = _ink,
    FontWeight weight = FontWeight.w400,
    double? maxWidth,
    int maxLines = 2,
  }) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: weight,
          height: 1.4,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: maxLines,
      ellipsis: '…',
    );
    painter.layout(maxWidth: maxWidth ?? (width - padding * 2));
    return painter;
  }

  static TextPainter? _optional(
    String? text, {
    required double size,
    required Color color,
    int maxLines = 2,
  }) {
    if (text == null || text.trim().isEmpty) return null;
    return _text(
      text.trim(),
      size: size,
      color: color,
      maxLines: maxLines,
    );
  }
}
