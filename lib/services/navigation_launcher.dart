import 'dart:io';

import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/location_mark.dart';
import '../models/nav_app.dart';
import '../utils/coordinate.dart';
import 'settings_controller.dart';

// NavApp 定义在模型层，这里转出去，调用方照旧只 import 本文件。
export '../models/nav_app.dart';

/// 唤起本机已安装的地图应用做导航。
///
/// 注意坐标系：高德 / 腾讯用 GCJ-02，百度支持带 `coord_type=gcj02` 的参数，
/// 苹果地图用 WGS-84。库里存的是 WGS-84，按目标应用分别转换。
class NavigationLauncher {
  NavigationLauncher._();

  static final NavigationLauncher instance = NavigationLauncher._();

  static const String _sourceApp = '地点标记';

  /// 组装各家地图的跳转链接。抽成纯函数方便测试。
  ///
  /// [mode] 是用户在设置页选的出行方式，各家地图的参数名都不一样，
  /// 在下面逐个映射；`geo:` 协议没有出行方式参数，只能忽略。
  static Uri buildUri(
    NavApp app, {
    required double latitude,
    required double longitude,
    required String name,
    TravelMode mode = TravelMode.driving,
  }) {
    final LatLngPair gcj =
        CoordinateConverter.wgs84ToGcj02(latitude, longitude);
    final String lat = gcj.latitude.toStringAsFixed(6);
    final String lng = gcj.longitude.toStringAsFixed(6);

    switch (app) {
      case NavApp.amap:
        final String scheme = Platform.isIOS ? 'iosamap' : 'androidamap';
        // 驾车走 navi，直接进转弯级导航；其余方式高德只支持路线规划页，
        // 换成 route/path 并用 t 指定方式。dev=0 表示传入的是 GCJ-02。
        if (mode == TravelMode.driving) {
          return Uri.parse(
            '$scheme://navi'
            '?sourceApplication=${Uri.encodeComponent(_sourceApp)}'
            '&lat=$lat&lon=$lng'
            '&poiname=${Uri.encodeComponent(name)}'
            '&dev=0&style=2',
          );
        }
        return Uri.parse(
          '$scheme://${Platform.isIOS ? 'path' : 'route'}'
          '?sourceApplication=${Uri.encodeComponent(_sourceApp)}'
          '&dlat=$lat&dlon=$lng'
          '&dname=${Uri.encodeComponent(name)}'
          '&dev=0&t=${_amapMode(mode)}',
        );
      case NavApp.baidu:
        return Uri.parse(
          'baidumap://map/direction'
          '?destination=name:${Uri.encodeComponent(name)}|latlng:$lat,$lng'
          '&coord_type=gcj02&mode=${_baiduMode(mode)}'
          '&src=${Uri.encodeComponent(_sourceApp)}',
        );
      case NavApp.tencent:
        return Uri.parse(
          'qqmap://map/routeplan?type=${_tencentMode(mode)}'
          '&tocoord=$lat,$lng'
          '&to=${Uri.encodeComponent(name)}'
          '&referer=${Uri.encodeComponent(_sourceApp)}',
        );
      case NavApp.appleMaps:
        // 苹果地图用 WGS-84，直接给原始坐标
        return Uri.parse(
          'http://maps.apple.com/?daddr='
          '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}'
          '&dirflg=${_appleMode(mode)}',
        );
      case NavApp.system:
        // Android 通用 geo: 协议，由系统选择地图应用
        return Uri.parse(
          'geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(name)})',
        );
    }
  }

  /// 高德 t 参数：0 驾车 / 1 公交 / 2 步行 / 3 骑行。
  static String _amapMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return '0';
      case TravelMode.transit:
        return '1';
      case TravelMode.walking:
        return '2';
      case TravelMode.riding:
        return '3';
    }
  }

  static String _baiduMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return 'driving';
      case TravelMode.walking:
        return 'walking';
      case TravelMode.riding:
        return 'riding';
      case TravelMode.transit:
        return 'transit';
    }
  }

  static String _tencentMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return 'drive';
      case TravelMode.walking:
        return 'walk';
      case TravelMode.riding:
        return 'bike';
      case TravelMode.transit:
        return 'bus';
    }
  }

  /// 苹果地图 dirflg 只有驾车 / 步行 / 公交，骑行归到步行。
  static String _appleMode(TravelMode mode) {
    switch (mode) {
      case TravelMode.driving:
        return 'd';
      case TravelMode.walking:
      case TravelMode.riding:
        return 'w';
      case TravelMode.transit:
        return 'r';
    }
  }

  /// 按当前设置的出行方式拼这条标记的跳转链接。
  static Uri _uriFor(NavApp app, LocationMark mark) => buildUri(
        app,
        latitude: mark.latitude,
        longitude: mark.longitude,
        name: mark.name,
        mode: SettingsController.instance.value.travelMode,
      );

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
      final Uri uri = _uriFor(app, mark);
      try {
        if (await canLaunchUrl(uri)) result.add(app);
      } catch (_) {
        // 查询失败按不可用处理
      }
    }
    return result;
  }

  Future<bool> launch(NavApp app, LocationMark mark) async {
    final Uri uri = _uriFor(app, mark);
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
