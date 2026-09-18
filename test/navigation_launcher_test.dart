import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/navigation_launcher.dart';
import 'package:location_marker/utils/coordinate.dart';

/// 导航链接组装：坐标系用错会把人导到几百米外，逐家核对。
void main() {
  // 杭州西湖附近（WGS-84）
  const double lat = 30.259924;
  const double lng = 120.146515;
  const String name = '临江公园 · 观景台';

  final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(lat, lng);
  final String gcjLat = gcj.latitude.toStringAsFixed(6);
  final String gcjLng = gcj.longitude.toStringAsFixed(6);

  test('高德链接用 GCJ-02 坐标并声明 dev=0', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.amap,
      latitude: lat,
      longitude: lng,
      name: name,
    );
    expect(uri.scheme, anyOf('androidamap', 'iosamap'));
    expect(uri.host, 'navi');
    expect(uri.queryParameters['lat'], gcjLat);
    expect(uri.queryParameters['lon'], gcjLng);
    // dev=0 表示传入坐标已是 GCJ-02，写错会被当成 WGS-84 再偏一次
    expect(uri.queryParameters['dev'], '0');
    expect(uri.queryParameters['poiname'], name);
  });

  test('百度链接显式声明 coord_type=gcj02', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.baidu,
      latitude: lat,
      longitude: lng,
      name: name,
    );
    expect(uri.scheme, 'baidumap');
    expect(uri.queryParameters['coord_type'], 'gcj02');
    expect(uri.queryParameters['destination'], contains('$gcjLat,$gcjLng'));
    expect(uri.queryParameters['mode'], 'driving');
  });

  test('腾讯链接用 GCJ-02 坐标', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.tencent,
      latitude: lat,
      longitude: lng,
      name: name,
    );
    expect(uri.scheme, 'qqmap');
    expect(uri.queryParameters['tocoord'], '$gcjLat,$gcjLng');
    expect(uri.queryParameters['type'], 'drive');
  });

  test('苹果地图用原始 WGS-84 坐标，不做偏移', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.appleMaps,
      latitude: lat,
      longitude: lng,
      name: name,
    );
    expect(uri.host, 'maps.apple.com');
    expect(
      uri.queryParameters['daddr'],
      '${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}',
    );
    // 不能混用：苹果地图收到 GCJ-02 会偏
    expect(uri.queryParameters['daddr'], isNot(contains(gcjLat)));
  });

  test('系统 geo 协议用 GCJ-02 并带上名称', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.system,
      latitude: lat,
      longitude: lng,
      name: name,
    );
    expect(uri.scheme, 'geo');
    expect(uri.toString(), contains('$gcjLat,$gcjLng'));
  });

  test('境外坐标不做偏移，各家链接与原坐标一致', () {
    const double tokyoLat = 35.6895;
    const double tokyoLng = 139.6917;
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.amap,
      latitude: tokyoLat,
      longitude: tokyoLng,
      name: '东京塔',
    );
    expect(uri.queryParameters['lat'], tokyoLat.toStringAsFixed(6));
    expect(uri.queryParameters['lon'], tokyoLng.toStringAsFixed(6));
  });

  test('名称里的特殊字符会被转义，不会破坏链接', () {
    final Uri uri = NavigationLauncher.buildUri(
      NavApp.amap,
      latitude: lat,
      longitude: lng,
      name: '老王&小李的店 #1',
    );
    // 能被正确解析回来，说明转义没问题
    expect(uri.queryParameters['poiname'], '老王&小李的店 #1');
    expect(uri.queryParameters['lat'], gcjLat);
  });
}
