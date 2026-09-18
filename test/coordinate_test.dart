import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/utils/coordinate.dart';

/// 坐标系转换：系统定位给 WGS-84，高德地图用 GCJ-02，
/// 转错了点会偏出几百米，所以这里逐条验证。
void main() {
  // 北京天安门、杭州西湖、广州塔（WGS-84 近似值）
  const List<(String, double, double)> chinaPoints = <(String, double, double)>[
    ('天安门', 39.908600, 116.397400),
    ('西湖', 30.259924, 120.146515),
    ('广州塔', 23.106600, 113.324500),
    ('哈尔滨', 45.803800, 126.534000),
    ('乌鲁木齐', 43.825600, 87.616800),
  ];

  test('中国境内 WGS-84 转 GCJ-02 会产生几百米的偏移', () {
    for (final (String name, double lat, double lng) in chinaPoints) {
      final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(lat, lng);
      final double offset = CoordinateConverter.distanceInMeters(
        lat,
        lng,
        gcj.latitude,
        gcj.longitude,
      );
      // 实际偏移量各地不同，量级稳定在百米级
      expect(offset, greaterThan(100), reason: '$name 偏移过小，可能没转换');
      expect(offset, lessThan(1000), reason: '$name 偏移过大，算法可能有误');
    }
  });

  test('GCJ-02 转回 WGS-84 能还原到厘米级', () {
    for (final (String name, double lat, double lng) in chinaPoints) {
      final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(lat, lng);
      final LatLngPair back =
          CoordinateConverter.gcj02ToWgs84(gcj.latitude, gcj.longitude);
      final double error = CoordinateConverter.distanceInMeters(
        lat,
        lng,
        back.latitude,
        back.longitude,
      );
      expect(error, lessThan(0.1), reason: '$name 往返误差过大');
    }
  });

  test('境外坐标不做偏移', () {
    const List<(String, double, double)> overseas =
        <(String, double, double)>[
      ('东京', 35.6895, 139.6917),
      ('纽约', 40.7128, -74.0060),
      ('悉尼', -33.8688, 151.2093),
    ];
    for (final (String name, double lat, double lng) in overseas) {
      final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(lat, lng);
      expect(gcj.latitude, lat, reason: '$name 纬度被改动');
      expect(gcj.longitude, lng, reason: '$name 经度被改动');

      final LatLngPair back = CoordinateConverter.gcj02ToWgs84(lat, lng);
      expect(back.latitude, lat);
      expect(back.longitude, lng);
    }
  });

  test('偏移方向符合 GCJ-02 的已知特征（东北向）', () {
    // 国内 GCJ-02 相对 WGS-84 普遍向东北偏
    final LatLngPair gcj =
        CoordinateConverter.wgs84ToGcj02(39.908600, 116.397400);
    expect(gcj.latitude, greaterThan(39.908600));
    expect(gcj.longitude, greaterThan(116.397400));
  });

  test('distanceInMeters 与已知距离吻合', () {
    // 北京到上海直线距离约 1067 公里
    final double d = CoordinateConverter.distanceInMeters(
      39.9042,
      116.4074,
      31.2304,
      121.4737,
    );
    expect(d / 1000, closeTo(1067, 30));

    // 同一点距离为 0
    expect(
      CoordinateConverter.distanceInMeters(30.0, 120.0, 30.0, 120.0),
      closeTo(0, 1e-6),
    );
  });
}
