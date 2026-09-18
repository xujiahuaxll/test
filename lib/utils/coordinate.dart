import 'dart:math';

/// 一对经纬度。
class LatLngPair {
  const LatLngPair(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  @override
  String toString() =>
      'LatLngPair(${latitude.toStringAsFixed(6)}, '
      '${longitude.toStringAsFixed(6)})';
}

/// WGS-84 与 GCJ-02（火星坐标）互转。
///
/// 系统定位（geolocator）给的是 WGS-84，高德地图用的是 GCJ-02，
/// 直接把 WGS-84 的点画到高德地图上会偏出几百米。
/// 库里统一存 WGS-84（标准坐标），只在与地图交互时转换。
class CoordinateConverter {
  CoordinateConverter._();

  static const double _a = 6378245.0; // 克拉索夫斯基椭球长半轴
  static const double _ee = 0.00669342162296594323; // 偏心率平方

  /// 粗略判断是否在中国境外：境外不做偏移。
  static bool outOfChina(double lat, double lng) {
    return lng < 72.004 || lng > 137.8347 || lat < 0.8293 || lat > 55.8271;
  }

  /// WGS-84 -> GCJ-02（存库坐标 -> 高德地图坐标）
  static LatLngPair wgs84ToGcj02(double lat, double lng) {
    if (outOfChina(lat, lng)) return LatLngPair(lat, lng);

    double dLat = _transformLat(lng - 105.0, lat - 35.0);
    double dLng = _transformLng(lng - 105.0, lat - 35.0);

    final double radLat = lat / 180.0 * pi;
    double magic = sin(radLat);
    magic = 1 - _ee * magic * magic;
    final double sqrtMagic = sqrt(magic);

    dLat = (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * pi);
    dLng = (dLng * 180.0) / (_a / sqrtMagic * cos(radLat) * pi);

    return LatLngPair(lat + dLat, lng + dLng);
  }

  /// GCJ-02 -> WGS-84（地图选点 -> 存库坐标）。
  /// 正变换没有解析反函数，这里用迭代逼近，几次就能收敛到厘米级。
  static LatLngPair gcj02ToWgs84(double lat, double lng) {
    if (outOfChina(lat, lng)) return LatLngPair(lat, lng);

    double wgsLat = lat;
    double wgsLng = lng;
    for (int i = 0; i < 10; i++) {
      final LatLngPair forward = wgs84ToGcj02(wgsLat, wgsLng);
      final double dLat = lat - forward.latitude;
      final double dLng = lng - forward.longitude;
      if (dLat.abs() < 1e-9 && dLng.abs() < 1e-9) break;
      wgsLat += dLat;
      wgsLng += dLng;
    }
    return LatLngPair(wgsLat, wgsLng);
  }

  /// 两点间距离（米），用于测试与「附近」类功能。
  static double distanceInMeters(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadius = 6371008.8;
    final double dLat = (lat2 - lat1) * pi / 180;
    final double dLng = (lng2 - lng1) * pi / 180;
    final double h = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLng / 2) *
            sin(dLng / 2);
    return 2 * earthRadius * asin(min(1, sqrt(h)));
  }

  static double _transformLat(double x, double y) {
    double ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0;
    ret += (160.0 * sin(y / 12.0 * pi) + 320 * sin(y * pi / 30.0)) * 2.0 / 3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    double ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * sqrt(x.abs());
    ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0;
    ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0;
    ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
