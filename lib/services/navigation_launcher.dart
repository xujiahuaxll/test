import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../models/location_mark.dart';
import '../utils/coordinate.dart';

/// 可以唤起的地图应用。
enum NavApp {
  amap('高德地图'),
  baidu('百度地图'),
  tencent('腾讯地图'),
  appleMaps('苹果地图'),
  system('系统默认地图');

  const NavApp(this.label);

  final String label;
}

/// 唤起本机已安装的地图应用做导航。
///
/// 注意坐标系：高德 / 腾讯用 GCJ-02，百度支持带 `coord_type=gcj02` 的参数，
/// 苹果地图用 WGS-84。库里存的是 WGS-84，按目标应用分别转换。
class NavigationLauncher {
  NavigationLauncher._();

  static final NavigationLauncher instance = NavigationLauncher._();

  static const String _sourceApp = '地点标记';

  /// 组装各家地图的跳转链接。抽成纯函数方便测试。
  static Uri buildUri(
    NavApp app, {
    required double latitude,
    required double longitude,
    required String name,
  }) {
    final LatLngPair gcj =
        CoordinateConverter.wgs84ToGcj02(latitude, longitude);
    final String lat = gcj.latitude.toStringAsFixed(6);
    final String lng = gcj.longitude.toStringAsFixed(6);

    switch (app) {
      case NavApp.amap:
        // dev=0 表示传入的是 GCJ-02 坐标，style=2 为导航（驾车）
        return Uri.parse(
          '${Platform.isIOS ? 'iosamap' : 'androidamap'}://navi'
          '?sourceApplication=${Uri.encodeComponent(_sourceApp)}'
          '&lat=$lat&lon=$lng'
          '&poiname=${Uri.encodeComponent(name)}'
          '&dev=0&style=2',
        );
      case NavApp.baidu:
        return Uri.parse(
          'baidumap://map/direction'
          '?destination=name:${Uri.encodeComponent(name)}|latlng:$lat,$lng'
          '&coord_type=gcj02&mode=driving'
          '&src=${Uri.encodeComponent(_sourceApp)}',
        );
      case NavApp.tencent:
        return Uri.parse(
          'qqmap://map/routeplan?type=drive'
          '&tocoord=$lat,$lng'
          '&to=${Uri.encodeComponent(name)}'
          '&referer=${Uri.encodeComponent(_sourceApp)}',
        );
      case NavApp.appleMaps:
        // 苹果地图用 WGS-84，直接给原始坐标
        return Uri.parse(
          'http://maps.apple.com/?daddr='
          '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}'
          '&dirflg=d',
        );
      case NavApp.system:
        // Android 通用 geo: 协议，由系统选择地图应用
        return Uri.parse(
          'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})',
        );
    }
  }

  /// 本机候选的地图应用（按平台过滤后再逐个探测是否可唤起）。
  static List<NavApp> candidates() {
    if (Platform.isIOS) {
      return <NavApp>[
        NavApp.amap,
        NavApp.baidu,
        NavApp.tencent,
        NavApp.appleMaps,
      ];
    }
    return <NavApp>[
      NavApp.amap,
      NavApp.baidu,
      NavApp.tencent,
      NavApp.system,
    ];
  }

  /// 探测哪些地图应用真的能唤起。
  Future<List<NavApp>> availableApps(LocationMark mark) async {
    final List<NavApp> result = <NavApp>[];
    for (final NavApp app in candidates()) {
      final Uri uri = buildUri(
        app,
        latitude: mark.latitude,
        longitude: mark.longitude,
        name: mark.name,
      );
      try {
        if (await canLaunchUrl(uri)) result.add(app);
      } catch (_) {
        // 查询失败按不可用处理
      }
    }
    return result;
  }

  Future<bool> launch(NavApp app, LocationMark mark) async {
    final Uri uri = buildUri(
      app,
      latitude: mark.latitude,
      longitude: mark.longitude,
      name: mark.name,
    );
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
