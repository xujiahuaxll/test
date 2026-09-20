import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/models/app_settings.dart';
import 'package:location_marker/services/navigation_launcher.dart';

/// 配置项的序列化：这层坏了会让用户的设置默默丢失，或者让 App 起不来。
void main() {
  test('默认配置是「每次询问 + 驾车 + 标准底图」', () {
    const AppSettings settings = AppSettings();
    expect(settings.defaultNavApp, isNull);
    expect(settings.travelMode, TravelMode.driving);
    expect(settings.mapKind, MapKind.standard);
    expect(settings.showTraffic, isFalse);
    expect(settings.reverseGeocode, isTrue);
    expect(settings.locateTimeout, const Duration(seconds: 20));
  });

  test('存进去再读回来，每一项都不变', () {
    const AppSettings original = AppSettings(
      defaultNavApp: NavApp.baidu,
      travelMode: TravelMode.riding,
      mapKind: MapKind.satellite,
      showTraffic: true,
      locateAccuracy: LocateAccuracy.powerSave,
      locateTimeoutSeconds: 60,
      reverseGeocode: false,
      audioQuality: AudioQuality.high,
      photoQuality: PhotoQuality.original,
      markerSort: MarkerSort.nameAsc,
    );

    final AppSettings restored = AppSettings.fromMap(original.toMap());

    expect(restored.toMap(), original.toMap());
    expect(restored.defaultNavApp, NavApp.baidu);
    expect(restored.travelMode, TravelMode.riding);
    expect(restored.photoQuality, PhotoQuality.original);
    expect(restored.markerSort, MarkerSort.nameAsc);
  });

  test('「每次询问」存成 ask，读回来是 null', () {
    const AppSettings settings = AppSettings();
    expect(
      settings.toMap()[AppSettings.keyDefaultNavApp],
      AppSettings.navAskEveryTime,
    );
    expect(AppSettings.fromMap(settings.toMap()).defaultNavApp, isNull);
  });

  test('空的 / 认不出的值一律回落到默认，不抛异常', () {
    expect(AppSettings.fromMap(<String, String>{}).toMap(),
        const AppSettings().toMap());

    final AppSettings garbage = AppSettings.fromMap(<String, String>{
      AppSettings.keyDefaultNavApp: '某个已经删掉的地图',
      AppSettings.keyTravelMode: '',
      AppSettings.keyMapKind: 'SATELLITE',
      AppSettings.keyShowTraffic: '1',
      AppSettings.keyMarkerSort: 'byDistance',
    });
    expect(garbage.defaultNavApp, isNull);
    expect(garbage.travelMode, TravelMode.driving);
    // 枚举名大小写敏感，认不出就用默认值
    expect(garbage.mapKind, MapKind.standard);
    expect(garbage.showTraffic, isFalse);
    expect(garbage.markerSort, MarkerSort.newestFirst);
  });

  test('超时只接受预设档位，越界值不会让定位永远等下去', () {
    for (final int seconds in kLocateTimeoutChoices) {
      expect(
        AppSettings.fromMap(<String, String>{
          AppSettings.keyLocateTimeout: '$seconds',
        }).locateTimeoutSeconds,
        seconds,
      );
    }
    for (final String bad in <String>['0', '-5', '99999', 'abc', '']) {
      expect(
        AppSettings.fromMap(<String, String>{
          AppSettings.keyLocateTimeout: bad,
        }).locateTimeoutSeconds,
        20,
        reason: '异常值 "$bad" 应该回落到默认的 20 秒',
      );
    }
  });

  test('copyWith 只改指定字段；清默认导航要用 clearDefaultNavApp', () {
    const AppSettings base = AppSettings(defaultNavApp: NavApp.amap);

    final AppSettings changed = base.copyWith(travelMode: TravelMode.transit);
    expect(changed.travelMode, TravelMode.transit);
    expect(changed.defaultNavApp, NavApp.amap);

    // 传 null 是「不改」，不是「清空」
    expect(base.copyWith().defaultNavApp, NavApp.amap);
    expect(base.copyWith(clearDefaultNavApp: true).defaultNavApp, isNull);
  });
}
