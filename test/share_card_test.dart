import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/models/location_mark.dart';
import 'package:location_marker/services/media_store.dart';
import 'package:location_marker/utils/coordinate.dart';
import 'package:location_marker/utils/marker_icon.dart';
import 'package:location_marker/utils/share_card.dart';
import 'package:path/path.dart' as p;

LocationMark markOf({
  String name = '老张家的面馆',
  String? address = '北京市东城区某条街 5 号',
  double latitude = 39.908722,
  double longitude = 116.397499,
  List<String> photos = const <String>[],
}) {
  return LocationMark(
    id: 'x',
    name: name,
    latitude: latitude,
    longitude: longitude,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
    address: address,
    photoPaths: photos,
  );
}

void main() {
  // 画图要真的建 Canvas 和解码 PNG，得先把引擎绑定起来。
  // 注意用 test 而不是 testWidgets：testWidgets 跑在假时钟里，
  // Picture.toImage 那个 Future 永远等不到，整个测试会挂死。
  TestWidgetsFlutterBinding.ensureInitialized();

  group('高德分享链接', () {
    test('用官方的 uri.amap.com，对方不用装这个 App', () {
      final Uri uri = Uri.parse(
        ShareLink.amapMarker(latitude: 39.9, longitude: 116.4, name: '某地'),
      );
      expect(uri.scheme, 'https');
      expect(uri.host, 'uri.amap.com');
      expect(uri.path, '/marker');
    });

    test('坐标先从 WGS-84 转成 GCJ-02，并声明 coordinate=gaode', () {
      // 不转的话在国内会偏出去几百米，直接指到隔壁街
      const double lat = 39.908722;
      const double lng = 116.397499;
      final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(lat, lng);
      final Uri uri = Uri.parse(
        ShareLink.amapMarker(latitude: lat, longitude: lng, name: '某地'),
      );

      expect(uri.queryParameters['coordinate'], 'gaode');
      final List<String> parts = uri.queryParameters['position']!.split(',');
      // 高德的 position 是「经度,纬度」，顺序反了就落到海里
      expect(double.parse(parts[0]), closeTo(gcj.longitude, 1e-6));
      expect(double.parse(parts[1]), closeTo(gcj.latitude, 1e-6));
      expect(double.parse(parts[0]), isNot(closeTo(lng, 1e-6)));
    });

    test('地点名带进链接，空名字给个兜底的', () {
      expect(
        Uri.parse(ShareLink.amapMarker(
          latitude: 39.9,
          longitude: 116.4,
          name: '老张家的面馆',
        )).queryParameters['name'],
        '老张家的面馆',
      );
      expect(
        Uri.parse(ShareLink.amapMarker(
          latitude: 39.9,
          longitude: 116.4,
          name: '   ',
        )).queryParameters['name'],
        '我标记的位置',
      );
    });

    test('名字里的特殊字符要转义，不能把链接撑坏', () {
      final String link = ShareLink.amapMarker(
        latitude: 39.9,
        longitude: 116.4,
        name: 'A&B=C 店 #1',
      );
      // 能原样解析回来才算转义对了
      expect(Uri.parse(link).queryParameters['name'], 'A&B=C 店 #1');
    });
  });

  group('分享文案', () {
    test('带上名字、地址和链接', () {
      final String text = ShareLink.caption(markOf());
      expect(text, contains('老张家的面馆'));
      expect(text, contains('北京市东城区某条街 5 号'));
      expect(text, contains('uri.amap.com'));
    });

    test('没有地址也不留空行', () {
      final String text = ShareLink.caption(markOf(address: null));
      expect(text, isNot(contains('\n\n')));
      expect(text, contains('uri.amap.com'));
    });

    test('地址是空白串时当没有', () {
      expect(ShareLink.caption(markOf(address: '   ')).split('\n'), hasLength(2));
    });
  });

  group('封面裁剪', () {
    test('宽图左右各切掉一点，高度全留', () {
      // 1000x500 的图放进 750x460 的框：源图更宽
      final Rect r = ShareCard.coverSrcRect(1000, 500, 750, 460);
      expect(r.height, 500);
      expect(r.width, lessThan(1000));
      expect(r.left, closeTo((1000 - r.width) / 2, 1e-6), reason: '要居中裁');
    });

    test('竖图上下各切掉一点，宽度全留', () {
      final Rect r = ShareCard.coverSrcRect(500, 1000, 750, 460);
      expect(r.width, 500);
      expect(r.height, lessThan(1000));
      expect(r.top, closeTo((1000 - r.height) / 2, 1e-6));
    });

    test('裁出来的比例和框一致——不一致就会把人压扁', () {
      for (final List<double> size in <List<double>>[
        <double>[4000, 3000],
        <double>[3000, 4000],
        <double>[1920, 1080],
      ]) {
        final Rect r = ShareCard.coverSrcRect(size[0], size[1], 750, 460);
        expect(r.width / r.height, closeTo(750 / 460, 1e-6));
      }
    });

    test('比例正好相等时整张都要，不多裁', () {
      final Rect r = ShareCard.coverSrcRect(750, 460, 750, 460);
      expect(r, const Rect.fromLTWH(0, 0, 750, 460));
    });

    test('尺寸为 0 的怪图不会算出 NaN 或除零', () {
      expect(ShareCard.coverSrcRect(0, 0, 750, 460), const Rect.fromLTWH(0, 0, 0, 0));
      expect(
        () => ShareCard.coverSrcRect(100, 100, 750, 0),
        returnsNormally,
      );
    });
  });

  group('真画一张出来', () {
    test('没有照片也能画，出来是一张像样的 PNG', () async {
      final Uint8List png = await ShareCard.render(markOf());

      // PNG 的固定文件头，画歪了或者编码失败都不会是这几个字节
      expect(png.sublist(0, 8), <int>[137, 80, 78, 71, 13, 10, 26, 10]);
      // 一张带二维码和文字的卡片不可能只有几百字节
      expect(png.length, greaterThan(5000));

      final Codec codec = await instantiateImageCodec(png);
      final FrameInfo frame = await codec.getNextFrame();
      expect(frame.image.width, ShareCard.width.round());
      expect(frame.image.height, greaterThan(300));
      frame.image.dispose();
      codec.dispose();
    });

    test('有封面时正好高出一个封面的高度', () async {
      final Directory root = await Directory.systemTemp.createTemp('share');
      addTearDown(() => root.delete(recursive: true));
      MediaStore.instance.overrideRootForTesting(root);

      final Directory photos = Directory(p.join(root.path, 'photos'));
      await photos.create(recursive: true);
      // 借画图标那套代码生成一张真 PNG 当封面
      await File(p.join(photos.path, 'cover.png')).writeAsBytes(
        await MarkerIcon.render(color: const Color(0xFF2F9E7E), pixelRatio: 4),
      );

      final int plain = await _heightOf(await ShareCard.render(markOf()));
      final int withCover = await _heightOf(
        await ShareCard.render(markOf(photos: <String>['photos/cover.png'])),
      );
      expect(withCover - plain, ShareCard.coverHeight.round());
    });

    test('照片文件不在了就按没有封面画，不是整张画不出来', () async {
      final Directory root = await Directory.systemTemp.createTemp('share');
      addTearDown(() => root.delete(recursive: true));
      MediaStore.instance.overrideRootForTesting(root);

      final int plain = await _heightOf(await ShareCard.render(markOf()));
      final int missing = await _heightOf(
        await ShareCard.render(markOf(photos: <String>['photos/nope.jpg'])),
      );
      expect(missing, plain);
    });

    test('标签和备注都齐的时候卡片会变高，内容没被挤掉', () async {
      final Uint8List plain = await ShareCard.render(markOf());
      final Uint8List rich = await ShareCard.render(
        LocationMark(
          id: 'y',
          name: '老张家的面馆',
          latitude: 39.9,
          longitude: 116.4,
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
          address: '北京市东城区某条街 5 号',
          tags: const <String>['美食', '打卡'],
          note: '二楼靠窗那桌，牛肉面加蛋，十一点前人少。',
        ),
      );
      expect(await _heightOf(rich), greaterThan(await _heightOf(plain)));
    });

    test('名字特别长也不会把卡片撑爆', () async {
      final Uint8List png = await ShareCard.render(
        markOf(name: '这是一个特别特别长的地点名字' * 10),
      );
      // 标题限了行数，高度应该还在一个合理范围里
      expect(await _heightOf(png), lessThan(1200));
    });
  });
}

/// 读出 PNG 的高度。
Future<int> _heightOf(Uint8List png) async {
  final Codec codec = await instantiateImageCodec(png);
  final FrameInfo frame = await codec.getNextFrame();
  final int height = frame.image.height;
  frame.image.dispose();
  codec.dispose();
  return height;
}
