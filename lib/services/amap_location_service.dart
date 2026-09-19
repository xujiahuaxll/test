import 'package:flutter/services.dart';

import '../models/app_settings.dart';
import '../utils/coordinate.dart';
import 'location_service.dart';

/// 高德定位。走 MethodChannel 调原生的 AMapLocationClient。
///
/// 为什么不用 geolocator：amap_map 插件只封装了地图，没有封装定位；而系统
/// 定位在国行机上要么依赖缺失的 Google Play 服务，要么精度差、地址解析常为空。
/// 高德定位一次调用就连中文地址一起返回，不需要再做一次逆地理编码。
class AmapLocationService {
  AmapLocationService._();

  static final AmapLocationService instance = AmapLocationService._();

  static const MethodChannel channel =
      MethodChannel('location_marker/amap_location');

  /// 原生侧传给 SDK 的定位模式标识。
  static String modeOf(LocateAccuracy accuracy) {
    switch (accuracy) {
      case LocateAccuracy.high:
        return 'high';
      case LocateAccuracy.balanced:
        return 'balanced';
      case LocateAccuracy.powerSave:
        return 'powerSave';
    }
  }

  /// 定一次位。失败时抛 [LocationFailure]，由调用方决定要不要回落系统定位。
  Future<LocationResult> locate({
    required String apiKey,
    required LocateAccuracy accuracy,
    required Duration timeout,
    required bool needAddress,
  }) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'locate',
        <String, Object?>{
          'apiKey': apiKey,
          'timeoutMs': timeout.inMilliseconds,
          'mode': modeOf(accuracy),
          'needAddress': needAddress,
        },
      );
    } on PlatformException catch (e) {
      throw LocationFailure(_kindOf(e.code), _messageOf(e));
    } on MissingPluginException {
      // 非 Android 平台没有这条通道
      throw const LocationFailure(
        LocationFailureKind.unknown,
        '当前平台不支持高德定位',
      );
    }

    if (raw == null) {
      throw const LocationFailure(
        LocationFailureKind.unknown,
        '高德定位没有返回结果',
      );
    }
    return parseResult(raw);
  }

  /// 把原生返回的 map 转成 [LocationResult]。抽出来方便测试。
  ///
  /// 高德给的是 GCJ-02，库里统一存 WGS-84，这里转回去；不转的话保存的坐标
  /// 会比真实位置偏出几百米，复制给其它地图也是错的。
  static LocationResult parseResult(Map<Object?, Object?> raw) {
    final double gcjLat = (raw['latitude'] as num).toDouble();
    final double gcjLng = (raw['longitude'] as num).toDouble();
    final LatLngPair wgs = CoordinateConverter.gcj02ToWgs84(gcjLat, gcjLng);
    final String address = (raw['address'] as String? ?? '').trim();

    return LocationResult(
      latitude: wgs.latitude,
      longitude: wgs.longitude,
      accuracy: (raw['accuracy'] as num?)?.toDouble() ?? 0,
      address: address.isEmpty ? null : address,
      source: LocationSource.amap,
    );
  }

  /// 高德的错误码分类，界面据此给不同的操作。
  /// 错误码含义见高德文档；这里只区分界面需要区别对待的几类。
  static LocationFailureKind _kindOf(String code) {
    switch (code) {
      case 'timeout':
        return LocationFailureKind.timeout;
      // 12 = 缺少定位权限，13 = 定位失败（权限/服务被关）
      case 'amap_12':
        return LocationFailureKind.denied;
      case 'amap_13':
        return LocationFailureKind.serviceDisabled;
      default:
        return LocationFailureKind.unknown;
    }
  }

  static String _messageOf(PlatformException e) {
    final String info = (e.message ?? '').trim();
    switch (e.code) {
      case 'timeout':
        return '高德定位超时，请到空旷处重试';
      case 'amap_12':
        return '没有定位权限，无法获取当前位置';
      case 'amap_13':
        return '定位失败，请检查系统定位是否开启';
      // 7 = Key 鉴权失败（包名或 SHA1 对不上）
      case 'amap_7':
        return '高德 Key 鉴权失败，请核对 Key 与包名、签名 SHA1';
      default:
        return info.isEmpty ? '高德定位失败（${e.code}）' : '高德定位失败：$info';
    }
  }
}
