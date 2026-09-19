import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

/// 定位失败的原因，界面按类型给不同的提示与操作。
enum LocationFailureKind { serviceDisabled, denied, deniedForever, timeout, unknown }

class LocationFailure implements Exception {
  const LocationFailure(this.kind, this.message);

  final LocationFailureKind kind;
  final String message;

  @override
  String toString() => 'LocationFailure($kind, $message)';
}

/// 一次定位的结果。address 可能为空（逆地理编码失败时界面回落显示经纬度）。
class LocationResult {
  const LocationResult({
    required this.latitude,
    required this.longitude,
    required this.accuracy,
    this.address,
  });

  final double latitude;
  final double longitude;
  final double accuracy;
  final String? address;
}

/// 系统定位（GPS / 网络定位）+ 系统逆地理编码，不接任何第三方地图服务。
class LocationService {
  LocationService._();

  static final LocationService instance = LocationService._();

  Future<LocationResult> current({
    Duration timeout = const Duration(seconds: 20),
  }) async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        '系统定位服务未开启，请在设置里打开定位',
      );
    }

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

    final Position position;
    try {
      position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: timeout,
        ),
      );
    } on LocationServiceDisabledException {
      throw const LocationFailure(
        LocationFailureKind.serviceDisabled,
        '系统定位服务未开启，请在设置里打开定位',
      );
    } catch (e) {
      throw LocationFailure(
        LocationFailureKind.timeout,
        '定位超时，请到空旷处重试（$e）',
      );
    }

    return LocationResult(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracy: position.accuracy,
      address: await _reverseGeocode(position.latitude, position.longitude),
    );
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
    final StringBuffer buffer = StringBuffer();
    for (final String part in parts) {
      if (part.isEmpty) continue;
      if (buffer.toString().contains(part)) continue;
      buffer.write(part);
    }
    final String result = buffer.toString();
    if (result.isNotEmpty) return result;
    final String fallback = mark.name ?? '';
    return fallback.isEmpty ? null : fallback;
  }
}
