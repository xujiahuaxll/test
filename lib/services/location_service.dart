import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/app_settings.dart';
import '../utils/coordinate.dart';
import 'amap_location_service.dart';
import 'amap_runtime.dart';
import 'settings_controller.dart';

/// 定位失败的原因，界面按类型给不同的提示与操作。
enum LocationFailureKind { serviceDisabled, denied, deniedForever, timeout, unknown }

class LocationFailure implements Exception {
  const LocationFailure(this.kind, this.message);

  final LocationFailureKind kind;
  final String message;

  @override
  String toString() => 'LocationFailure($kind, $message)';
}

/// 这次坐标是谁给的。地址解析不出来时，界面据此告诉用户该查什么。
enum LocationSource {
  amap('高德定位'),
  system('系统定位');

  const LocationSource(this.label);

  final String label;
}

/// 一次定位的结果。address 可能为空（逆地理编码失败时界面回落显示经纬度）。
class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.address,
    this.placeName,
    this.source = LocationSource.system,
    this.note,
  });

  final double latitude;
  final double longitude;
  final double accuracy;

  /// 详细地址：「北京市大兴区天河北路5号」。
  final String? address;

  /// 地点名：「中铁吉盛」。做标题，地址做副标题。
  final String? placeName;

  /// 坐标的来源。
  final LocationSource source;

  /// 降级说明：回落了、或者地址没解析出来时的原因。正常情况下为 null。
  final String? note;

  LocationResult copyWith({
    String? address,
    String? placeName,
    String? note,
  }) =>
      LocationResult(
        latitude: latitude,
        longitude: longitude,
        accuracy: accuracy,
        address: address ?? this.address,
        placeName: placeName ?? this.placeName,
        source: source,
        note: note ?? this.note,
      );

  /// 标题：地点名优先，没有就用地址。
  String? get title => placeName?.isNotEmpty == true ? placeName : address;

  /// 副标题：标题已经是地点名时才补详细地址。
  String? get subtitle =>
      placeName?.isNotEmpty == true && address?.isNotEmpty == true
          ? address
          : null;
}

/// 系统定位（GPS / 网络定位）+ 系统逆地理编码，不接任何第三方地图服务。
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  /// 精度、超时、是否解析地址都取设置页的值；传参可覆盖，方便测试。
  Future<LocationResult> current({
    Duration? timeout,
    LocateAccuracy? accuracy,
    bool? resolveAddress,
  }) async {
    final AppSettings settings = SettingsController.instance.value;
    final Duration limit = timeout ?? settings.locateTimeout;
    final LocateAccuracy wanted = accuracy ?? settings.locateAccuracy;
    final bool wantAddress = resolveAddress ?? settings.reverseGeocode;
    _lastAmapFailure = null;

    // 先要权限，再谈定位服务。
    //
    // 原来是反过来的：一上来先问 Geolocator.isLocationServiceEnabled()。
    // 那个调用在检测到 Google Play 服务时会去问 GMS 的 SettingsClient，
    // 国行机上 GMS 往往缺失或不可用，调用失败就被当成「定位服务未开启」——
    // 于是定位明明开着也报未开启，而且因为卡在第一步，权限框根本没机会弹。
    // 服务到底开没开，交给下面真正取位置时由系统 LocationManager 来判断。
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      throw const LocationFailure(
        LocationFailureKind.deniedForever,
        '定位权限已被永久拒绝，请到系统设置里重新允许',
      );
    }
    if (permission == LocationPermission.denied) {
      throw const LocationFailure(
        LocationFailureKind.denied,
        '没有定位权限，无法获取当前位置',
      );
    }

    // 配了高德 Key 且已同意隐私声明时优先用高德定位：国内精度更好，
    // 不依赖 Google Play 服务，而且直接带回中文地址。
    // 它失败了再回落系统定位，不让用户卡在这一步。
    if (useAmap) {
      try {
        final LocationResult amap = await AmapLocationService.instance.locate(
          apiKey: AmapRuntime.instance.effectiveKey,
          accuracy: wanted,
          timeout: limit,
          needAddress: wantAddress,
        );
        if (!wantAddress) return amap;
        return await _withPlaceName(amap);
      } on LocationFailure catch (failure) {
        // 权限类问题回落也没用，直接抛给界面
        if (failure.kind == LocationFailureKind.denied ||
            failure.kind == LocationFailureKind.deniedForever) {
          rethrow;
        }
        _lastAmapFailure = failure;
      }
    }

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: buildLocationSettings(wanted, limit),
      );
    } on LocationServiceDisabledException {
      // 这个是系统 LocationManager 给的结论（GPS 与网络定位都关着），可信。
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        '系统定位服务未开启，请在设置里打开定位',
      );
    } on TimeoutException {
      throw LocationFailure(
        LocationFailureKind.timeout,
        _withAmapReason('定位超时（${limit.inSeconds} 秒），请到空旷处重试'),
      );
    } catch (e) {
      throw LocationFailure(
        LocationFailureKind.unknown,
        _withAmapReason('定位失败：$e'),
      );
    }

    final String? address = wantAddress
        ? await _reverseGeocode(position.latitude, position.longitude)
        : null;
    final LocationFailure? amapFailure = _lastAmapFailure;

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: address,
      source: LocationSource.system,
      note: _systemNote(
        amapFailure: amapFailure,
        missingAddress: wantAddress && address == null,
      ),
    );
  }

  /// 把坐标换成一个像样的「地点名」。
  ///
  /// 定位结果自带的 address 只是一条街道地址（还经常为空），而用户要的是
  /// 「某某大厦」「某某景区」。所以再走一次高德的逆地理编码，它会返回附近
  /// 的 POI；都拿不到才退回系统逆地理编码。
  Future<LocationResult> _withPlaceName(LocationResult located) async {
    // 周边搜索只认 GCJ-02，这里转一次给它用；逆地理编码仍传 WGS-84。
    final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(
      located.latitude,
      located.longitude,
    );
    try {
      final AmapPlaces places = await AmapLocationService.instance.nearbyPlaces(
        apiKey: AmapRuntime.instance.effectiveKey,
        latitude: located.latitude,
        longitude: located.longitude,
      );
      final String? full =
          places.formatAddress.isEmpty ? null : places.formatAddress;

      // 地点名优先用周边搜索的最近结果：它按距离排序、楼宇也搜得到，
      // 能给到「XX号楼」这一级；逆地理编码常常只到小区或街道。
      String? name = places.bestName;
      try {
        final List<AmapPlace> nearby =
            await AmapLocationService.instance.nearbyPois(
          apiKey: AmapRuntime.instance.effectiveKey,
          latitude: gcj.latitude,
          longitude: gcj.longitude,
          radius: 500,
        );
        if (nearby.isNotEmpty) name = nearby.first.title;
      } on LocationFailure {
        // 拿不到就用逆地理编码给的那个，不影响主流程
      }

      // 地点名取不到也没关系，有整句地址就够界面显示了。
      if (name != null || full != null) {
        return located.copyWith(placeName: name, address: full);
      }
    } on LocationFailure catch (failure) {
      // 逆地理失败不影响已经拿到的坐标，记下原因继续往下兜底
      if (located.address != null) {
        return located.copyWith(note: '没能取到附近地点名（${failure.message}）');
      }
    }

    if (located.address != null) return located;

    final String? system =
        await _reverseGeocode(located.latitude, located.longitude);
    return located.copyWith(
      address: system,
      note: system == null ? '高德和系统都没解析出地址，通常是当时网络不通' : null,
    );
  }

  /// 走到系统定位这一步时，把「为什么没用高德」「为什么没有地址」说清楚，
  /// 否则界面只有一句「未获取到地址」，没人知道该查 Key 还是查网络。
  static String? _systemNote({
    required LocationFailure? amapFailure,
    required bool missingAddress,
  }) {
    final List<String> parts = <String>[];
    if (amapFailure != null) {
      parts.add('高德定位失败（${amapFailure.message}），已回落系统定位');
    } else {
      // 压根没走高德那条路，说清楚是缺什么——上一版漏了这句，
      // 结果界面显示「系统定位」却看不出原因。
      final AmapRuntime runtime = AmapRuntime.instance;
      if (!runtime.hasKey) {
        parts.add('没有可用的高德 Key，用的是系统定位');
      } else if (!runtime.privacyAgreed.value) {
        parts.add('未同意高德隐私声明，用的是系统定位');
      }
    }
    if (missingAddress) {
      parts.add('系统未能解析出地址，只记录了坐标');
    }
    return parts.isEmpty ? null : parts.join('；');
  }

  /// 组装取位置用的参数。Android 上强制走系统 LocationManager。
  ///
  /// geolocator 检测到 Google Play 服务时会默认改用 FusedLocationProvider，
  /// 那条路径上的定位服务判断依赖 GMS；国行机上 GMS 缺失或残缺会让它直接
  /// 报错。系统 LocationManager 没有这个依赖，任何设备上都能用，代价是
  /// 少了 GMS 的传感器融合，室内首次定位可能稍慢一点。
  /// 高德定位那次失败的原因，用来在系统定位也失败时一并说清楚。
  LocationFailure? _lastAmapFailure;

  /// 是否该用高德定位：配了 Key 且用户已同意隐私声明。
  /// 抽成 getter 方便测试覆盖判定条件。
  bool get useAmap => AmapRuntime.instance.mapReady;

  String _withAmapReason(String message) {
    final LocationFailure? amap = _lastAmapFailure;
    if (amap == null) return message;
    return '$message（高德定位也失败了：${amap.message}）';
  }

  /// [android] 只为测试留的注入口，正常调用不传，取当前平台。
  static LocationSettings buildLocationSettings(
    LocateAccuracy accuracy,
    Duration limit, {
    bool? android,
  }) {
    final LocationAccuracy mapped = _accuracyOf(accuracy);
    if (android ?? Platform.isAndroid) {
      return AndroidSettings(
        accuracy: mapped,
        timeLimit: limit,
        forceLocationManager: true,
      );
    }
    return LocationSettings(accuracy: mapped, timeLimit: limit);
  }

  static LocationAccuracy _accuracyOf(LocateAccuracy accuracy) {
    switch (accuracy) {
      case LocateAccuracy.high:
        return LocationAccuracy.high;
      case LocateAccuracy.balanced:
        return LocationAccuracy.medium;
      case LocateAccuracy.powerSave:
        return LocationAccuracy.low;
    }
  }

  /// 逆地理编码走系统能力（iOS CLGeocoder / Android Geocoder），
  /// 没有 API Key；失败时返回 null，界面退回显示经纬度。
  Future<String?> _reverseGeocode(double lat, double lng) async {
    try {
      // 让系统按中文返回地址字段。
      final List<Placemark> marks = await Geocoding().placemarkFromCoordinates(
        lat,
        lng,
        locale: const Locale('zh', 'CN'),
      );
      if (marks.isEmpty) return null;
      return formatPlacemark(marks.first);
    } catch (_) {
      return null;
    }
  }

  /// 把系统返回的地址字段拼成「省市区街道门牌」。
  static String? formatPlacemark(Placemark mark) {
    final List<String> parts = <String>[
      mark.administrativeArea ?? '',
      mark.locality ?? '',
      mark.subLocality ?? '',
      mark.thoroughfare ?? '',
      mark.subThoroughfare ?? '',
    ];
    // 英文地址的各段之间必须留空格，否则会糊成
    // 「Tianhe North RoadNo.5」这种读不通的东西；中文地址本来就不用空格。
    final List<String> kept = <String>[];
    for (final String part in parts) {
      if (part.isEmpty) continue;
      if (kept.any((String seen) => seen.contains(part))) continue;
      kept.add(part);
    }
    final bool hasLatin = kept.any((String p) => RegExp('[A-Za-z]').hasMatch(p));
    final String result = kept.join(hasLatin ? ' ' : '');
    if (result.isNotEmpty) return result;
    final String fallback = mark.name ?? '';
    return fallback.isEmpty ? null : fallback;
  }
}
