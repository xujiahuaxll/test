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

    return LocationResult(
      latitude: wgs.latitude,
      longitude: wgs.longitude,
      accuracy: (raw['accuracy'] as num?)?.toDouble() ?? 0,
      address: pickFullAddress(raw),
      placeName: pickPlaceName(raw),
      source: LocationSource.amap,
    );
  }

  /// 地点名：「某某大厦」「某某园区」。做标题用。
  static String? pickPlaceName(Map<Object?, Object?> raw) {
    for (final String key in <String>['poiName', 'aoiName']) {
      final String value = (raw[key] as String? ?? '').trim();
      if (value.isNotEmpty) return value;
    }
    return null;
  }

  /// 详细地址：「某路某号」。做副标题用。
  static String? pickFullAddress(Map<Object?, Object?> raw) {
    String read(String key) => (raw[key] as String? ?? '').trim();

    final String address = read('address');
    if (address.isNotEmpty) return address;

    // 只剩零散字段时自己拼一条
    final List<String> parts = <String>[
      read('district'),
      read('street'),
      read('streetNum'),
    ].where((String p) => p.isNotEmpty).toList();
    return parts.isEmpty ? null : parts.join('');
  }

  /// 读本安装包的包名与签名 SHA1。
  ///
  /// 到高德开放平台登记 Key 时要填这两个值。放进设置页，换一版包自己
  /// 就能核对、改绑，不用去翻构建日志。
  Future<AppSignature?> appSignature() async {
    try {
      final Map<Object?, Object?>? raw =
          await channel.invokeMethod<Map<Object?, Object?>>('appSignature');
      if (raw == null) return null;
      return AppSignature(
        packageName: (raw['packageName'] as String? ?? '').trim(),
        sha1: (raw['sha1'] as String? ?? '').trim(),
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      // 非 Android 平台没有这条通道
      return null;
    }
  }

  /// 逆地理编码：拿坐标换格式化地址与附近 POI。
  ///
  /// 传 WGS-84（库里存的口径），原生侧用 GeocodeSearch.GPS 让高德自己换算。
  Future<AmapPlaces> nearbyPlaces({
    required String apiKey,
    required double latitude,
    required double longitude,
    int radius = 200,
    bool gcj = false,
  }) async {
    final Map<Object?, Object?>? raw;
    try {
      raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'regeo',
        <String, Object?>{
          'apiKey': apiKey,
          'latitude': latitude,
          'longitude': longitude,
          'radius': radius,
          'gcj': gcj,
        },
      );
    } on PlatformException catch (e) {
      throw LocationFailure(LocationFailureKind.unknown, regeoMessage(e));
    } on MissingPluginException {
      throw const LocationFailure(
        LocationFailureKind.unknown,
        '当前平台不支持高德逆地理编码',
      );
    }
    if (raw == null) {
      throw const LocationFailure(
        LocationFailureKind.unknown,
        '逆地理编码没有返回结果',
      );
    }
    return AmapPlaces.fromMap(raw);
  }

  /// 把逆地理编码的错误翻成能照着做的话。
  ///
  /// 之前这里只显示原生传来的 message，把错误码丢了——而码才是区分
  /// 「Key 不对」和「连不上网」的唯一依据。现在一律带上。
  static String regeoMessage(PlatformException e) {
    final int? code = int.tryParse(e.code.replaceFirst('regeo_', ''));
    final String suffix = code == null ? '（${e.code}）' : '（错误码 $code）';
    switch (code) {
      case 1001:
      case 1002:
        return 'Key 无效或未授权，请核对 Key 与包名、签名 SHA1$suffix';
      case 1003:
        return 'Key 没有开通「搜索」服务，请到高德后台检查$suffix';
      case 1802:
      case 1804:
      case 1806:
        return '连不上高德服务器，请检查网络或关掉 VPN 再试$suffix';
      case 1008:
        return 'Key 对应的包名与本应用不一致$suffix';
      case 1009:
        return 'Key 对应的签名 SHA1 与本安装包不一致$suffix';
      default:
        final String info = (e.message ?? '').trim();
        return info.isEmpty ? '获取附近地点失败$suffix' : info;
    }
  }

  /// 输入提示：边打字边给候选。[latitude]/[longitude] 是 GCJ-02，用来做
  /// 距离偏置，同名地点近的排前面。
  Future<List<AmapPlace>> inputTips({
    required String apiKey,
    required String keyword,
    double? latitude,
    double? longitude,
    String city = '',
  }) async {
    if (keyword.trim().isEmpty) return const <AmapPlace>[];
    return _listCall('inputTips', <String, Object?>{
      'apiKey': apiKey,
      'keyword': keyword.trim(),
      'city': city,
      'latitude': latitude,
      'longitude': longitude,
    }, '搜索失败');
  }

  /// 周边搜索：列出这个点附近有哪些地方，按距离由近到远。
  ///
  /// 坐标是 GCJ-02。比逆地理编码自带的 POI 列表准，楼宇这类也搜得到。
  Future<List<AmapPlace>> nearbyPois({
    required String apiKey,
    required double latitude,
    required double longitude,
    int radius = 1000,
    String keyword = '',
  }) {
    return _listCall('nearbyPois', <String, Object?>{
      'apiKey': apiKey,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'keyword': keyword,
    }, '获取附近地点失败');
  }

  Future<List<AmapPlace>> _listCall(
    String method,
    Map<String, Object?> args,
    String fallbackMessage,
  ) async {
    try {
      final List<Object?>? raw =
          await channel.invokeMethod<List<Object?>>(method, args);
      return AmapPlace.listFrom(raw);
    } on PlatformException catch (e) {
      final String info = (e.message ?? '').trim();
      throw LocationFailure(
        LocationFailureKind.unknown,
        info.isEmpty ? '$fallbackMessage（${e.code}）' : info,
      );
    } on MissingPluginException {
      throw LocationFailure(
        LocationFailureKind.unknown,
        '当前平台不支持$fallbackMessage',
      );
    }
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
        return info.isEmpty
            ? '高德定位失败（${e.code}）'
            : '高德定位失败：$info（${e.code}）';
    }
  }
}

/// 附近的一个地点。
class AmapPlace {
  const AmapPlace({
    required this.title,
    required this.distance,
    this.snippet = '',
    this.latitude,
    this.longitude,
  });

  final String title;

  /// 这个地点自己的 GCJ-02 坐标。选中它时把图钉挪过去用。
  /// 输入提示里个别条目（公交线路之类）没有坐标，那种已在原生侧滤掉。
  final double? latitude;
  final double? longitude;

  bool get hasPoint => latitude != null && longitude != null;

  /// 距离当前位置多少米。
  final int distance;

  /// 这个 POI 的街道地址，给用户区分同名地点用。
  final String snippet;

  String get distanceText =>
      distance < 1000 ? '$distance 米' : '${(distance / 1000).toStringAsFixed(1)} 公里';

  static AmapPlace fromMap(Map<Object?, Object?> raw) => AmapPlace(
        title: (raw['title'] as String? ?? '').trim(),
        distance: (raw['distance'] as num?)?.toInt() ?? 0,
        snippet: (raw['snippet'] as String? ?? '').trim(),
        latitude: (raw['latitude'] as num?)?.toDouble(),
        longitude: (raw['longitude'] as num?)?.toDouble(),
      );

  static List<AmapPlace> listFrom(Object? raw) => <AmapPlace>[
        for (final Object? item in (raw as List<Object?>? ?? const <Object?>[]))
          if (item is Map<Object?, Object?>) AmapPlace.fromMap(item),
      ].where((AmapPlace p) => p.title.isNotEmpty).toList(growable: false);
}

/// 一次逆地理编码的结果。
class AmapPlaces {
  const AmapPlaces({
    required this.formatAddress,
    required this.places,
    this.building = '',
    this.aoiName = '',
  });

  /// 「北京市大兴区天河北路5号」这种整句地址。
  final String formatAddress;

  /// 附近的 POI，已按距离从近到远排好。
  final List<AmapPlace> places;

  final String building;
  final String aoiName;

  /// 最贴切的一个地点名：楼宇 > 最近的 POI > 园区。
  ///
  /// 取不到就返回 null，**不回落到整句地址**——回落的话标题和副标题
  /// 会变成同一句话，等于白占一行。上层拿到 null 时自己用地址当标题。
  ///
  /// POI 排在园区前面是因为它更具体：站在小区里，POI 可能是
  /// 「双河北里小区-乙27号楼」，而园区名只有「双河北里小区」。
  String? get bestName {
    final String buildingName = building.trim();
    if (buildingName.isNotEmpty) return buildingName;

    if (places.isNotEmpty && places.first.title.isNotEmpty) {
      return places.first.title;
    }
    final String aoi = aoiName.trim();
    return aoi.isEmpty ? null : aoi;
  }

  static AmapPlaces fromMap(Map<Object?, Object?> raw) {
    final List<Object?> rawPois =
        (raw['pois'] as List<Object?>? ?? const <Object?>[]);
    return AmapPlaces(
      formatAddress: (raw['formatAddress'] as String? ?? '').trim(),
      building: (raw['building'] as String? ?? '').trim(),
      aoiName: (raw['aoiName'] as String? ?? '').trim(),
      places: <AmapPlace>[
        for (final Object? item in rawPois)
          if (item is Map<Object?, Object?>)
            AmapPlace.fromMap(item),
      ].where((AmapPlace p) => p.title.isNotEmpty).toList(growable: false),
    );
  }
}

/// 本安装包的身份：到高德后台登记 Key 时要填这两个。
class AppSignature {
  const AppSignature({required this.packageName, required this.sha1});

  final String packageName;
  final String sha1;

  bool get isUsable => packageName.isNotEmpty && sha1.isNotEmpty;
}
