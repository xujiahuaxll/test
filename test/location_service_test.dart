import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:location_marker/models/app_settings.dart';
import 'package:location_marker/services/location_service.dart';

/// 定位参数的组装。Android 上必须绕开 Google Play 服务，
/// 否则国行机上定位明明开着也会被报成「服务未开启」。
void main() {
  group('buildLocationSettings', () {
    test('Android 上强制走系统 LocationManager，绕开 Google Play 服务', () {
      final LocationSettings settings = LocationService.buildLocationSettings(
        LocateAccuracy.high,
        const Duration(seconds: 20),
        android: true,
      );
      expect(settings, isA<AndroidSettings>());
      // 这一条就是本次修复的核心：为 false 时国行机会误报「定位服务未开启」
      expect((settings as AndroidSettings).forceLocationManager, isTrue);
    });

    test('非 Android 平台用通用参数，不牵扯 Android 专属设置', () {
      final LocationSettings settings = LocationService.buildLocationSettings(
        LocateAccuracy.high,
        const Duration(seconds: 20),
        android: false,
      );
      expect(settings, isNot(isA<AndroidSettings>()));
    });

    test('超时按传入的值设置', () {
      for (final int seconds in kLocateTimeoutChoices) {
        final LocationSettings settings = LocationService.buildLocationSettings(
          LocateAccuracy.balanced,
          Duration(seconds: seconds),
          android: true,
        );
        expect(settings.timeLimit, Duration(seconds: seconds));
      }
    });

    test('三档精度分别映射到 geolocator 的精度枚举，互不相同', () {
      LocationAccuracy accuracyOf(LocateAccuracy a) =>
          LocationService.buildLocationSettings(
            a,
            const Duration(seconds: 20),
            android: true,
          ).accuracy;

      expect(accuracyOf(LocateAccuracy.high), LocationAccuracy.high);
      expect(accuracyOf(LocateAccuracy.balanced), LocationAccuracy.medium);
      expect(accuracyOf(LocateAccuracy.powerSave), LocationAccuracy.low);

      // 三档必须真的不一样，否则设置页的选项是摆设
      final Set<LocationAccuracy> mapped =
          LocateAccuracy.values.map(accuracyOf).toSet();
      expect(mapped.length, LocateAccuracy.values.length);
    });
  });

  group('formatPlacemark', () {
    Placemark mark({
      String admin = '',
      String locality = '',
      String subLocality = '',
      String thoroughfare = '',
      String subThoroughfare = '',
      String name = '',
    }) =>
        Placemark(
          administrativeArea: admin,
          locality: locality,
          subLocality: subLocality,
          thoroughfare: thoroughfare,
          subThoroughfare: subThoroughfare,
          name: name,
        );

    test('英文地址各段之间要有空格，不能糊成一串', () {
      // 之前会拼成 BeijingDaxingTianhe North RoadNo.5
      expect(
        LocationService.formatPlacemark(mark(
          admin: 'Beijing',
          subLocality: 'Daxing',
          thoroughfare: 'Tianhe North Road',
          subThoroughfare: 'No.5',
        )),
        'Beijing Daxing Tianhe North Road No.5',
      );
    });

    test('中文地址不加空格', () {
      expect(
        LocationService.formatPlacemark(mark(
          admin: '北京市',
          subLocality: '大兴区',
          thoroughfare: '天河北路',
          subThoroughfare: '5号',
        )),
        '北京市大兴区天河北路5号',
      );
    });

    test('重复的段只保留一次', () {
      expect(
        LocationService.formatPlacemark(mark(
          admin: '北京市',
          locality: '北京市',
          subLocality: '大兴区',
        )),
        '北京市大兴区',
      );
    });

    test('全空时退回 name，name 也空则返回 null', () {
      expect(LocationService.formatPlacemark(mark(name: '某大厦')), '某大厦');
      expect(LocationService.formatPlacemark(mark()), isNull);
    });
  });
}
