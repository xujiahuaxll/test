import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/models/app_settings.dart';
import 'package:location_marker/services/amap_location_service.dart';
import 'package:location_marker/services/location_service.dart';
import 'package:location_marker/utils/coordinate.dart';

/// 高德定位这条通道：坐标系转换错了会把标记存到几百米外，
/// 错误分类错了界面会给出误导性的操作提示。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final AmapLocationService service = AmapLocationService.instance;

  /// 给 MethodChannel 打桩：成功时返回 payload，失败时抛 PlatformException。
  void stub({
    Map<Object?, Object?>? payload,
    PlatformException? error,
    void Function(MethodCall call)? onCall,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AmapLocationService.channel,
            (MethodCall call) async {
      onCall?.call(call);
      if (error != null) throw error;
      return payload;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AmapLocationService.channel, null);
  });

  group('parseResult', () {
    test('高德给的 GCJ-02 会转回 WGS-84 再存', () {
      // 杭州西湖附近的真实 WGS-84 坐标
      const double wgsLat = 30.259924;
      const double wgsLng = 120.146515;
      final LatLngPair gcj =
          CoordinateConverter.wgs84ToGcj02(wgsLat, wgsLng);

      final LocationResult result =
          AmapLocationService.parseResult(<Object?, Object?>{
        'latitude': gcj.latitude,
        'longitude': gcj.longitude,
        'accuracy': 12.5,
        'address': '浙江省杭州市西湖区北山街',
      });

      // 转回来要能还原到米级以内
      expect(
        CoordinateConverter.distanceInMeters(
          result.latitude,
          result.longitude,
          wgsLat,
          wgsLng,
        ),
        lessThan(1),
      );
      expect(result.accuracy, 12.5);
      expect(result.address, '浙江省杭州市西湖区北山街');
    });

    test('直接用高德原始坐标会明显偏移，所以转换不能省', () {
      const double wgsLat = 39.909187;
      const double wgsLng = 116.397451;
      final LatLngPair gcj =
          CoordinateConverter.wgs84ToGcj02(wgsLat, wgsLng);

      // 不转换的话偏差有几百米
      expect(
        CoordinateConverter.distanceInMeters(
          gcj.latitude,
          gcj.longitude,
          wgsLat,
          wgsLng,
        ),
        greaterThan(100),
      );
    });

    test('地址为空串时归一成 null，界面才会回落显示经纬度', () {
      final LocationResult result =
          AmapLocationService.parseResult(<Object?, Object?>{
        'latitude': 30.0,
        'longitude': 120.0,
        'accuracy': 8,
        'address': '   ',
      });
      expect(result.address, isNull);
    });

    test('缺少精度字段时补 0，不抛异常', () {
      final LocationResult result =
          AmapLocationService.parseResult(<Object?, Object?>{
        'latitude': 30.0,
        'longitude': 120.0,
      });
      expect(result.accuracy, 0);
      expect(result.address, isNull);
    });
  });

  group('locate', () {
    test('把设置里的精度与超时如实传给原生侧', () async {
      MethodCall? seen;
      stub(
        payload: <Object?, Object?>{
          'latitude': 30.0,
          'longitude': 120.0,
          'accuracy': 5,
          'address': '某地',
        },
        onCall: (MethodCall call) => seen = call,
      );

      await service.locate(
        apiKey: 'k' * 32,
        accuracy: LocateAccuracy.powerSave,
        timeout: const Duration(seconds: 30),
        needAddress: false,
      );

      expect(seen!.method, 'locate');
      final Map<Object?, Object?> args =
          seen!.arguments as Map<Object?, Object?>;
      expect(args['apiKey'], 'k' * 32);
      expect(args['mode'], 'powerSave');
      expect(args['timeoutMs'], 30000);
      expect(args['needAddress'], isFalse);
    });

    test('三档精度各自对应一个模式标识，互不相同', () {
      final Set<String> modes =
          LocateAccuracy.values.map(AmapLocationService.modeOf).toSet();
      expect(modes.length, LocateAccuracy.values.length);
      expect(AmapLocationService.modeOf(LocateAccuracy.high), 'high');
    });

    test('权限类错误单独归类，界面才能引导去授权', () async {
      stub(error: PlatformException(code: 'amap_12', message: '缺少定位权限'));
      await expectLater(
        service.locate(
          apiKey: 'k' * 32,
          accuracy: LocateAccuracy.high,
          timeout: const Duration(seconds: 20),
          needAddress: true,
        ),
        throwsA(
          isA<LocationFailure>().having(
            (LocationFailure f) => f.kind,
            'kind',
            LocationFailureKind.denied,
          ),
        ),
      );
    });

    test('超时单独归类', () async {
      stub(error: PlatformException(code: 'timeout', message: ''));
      await expectLater(
        service.locate(
          apiKey: 'k' * 32,
          accuracy: LocateAccuracy.high,
          timeout: const Duration(seconds: 20),
          needAddress: true,
        ),
        throwsA(
          isA<LocationFailure>().having(
            (LocationFailure f) => f.kind,
            'kind',
            LocationFailureKind.timeout,
          ),
        ),
      );
    });

    test('Key 鉴权失败给出能照着排查的提示', () async {
      stub(error: PlatformException(code: 'amap_7', message: 'INVALID_USER_KEY'));
      await expectLater(
        service.locate(
          apiKey: 'k' * 32,
          accuracy: LocateAccuracy.high,
          timeout: const Duration(seconds: 20),
          needAddress: true,
        ),
        throwsA(
          isA<LocationFailure>().having(
            (LocationFailure f) => f.message,
            'message',
            allOf(contains('Key'), contains('SHA1')),
          ),
        ),
      );
    });

    test('原生返回空时报错而不是当成定位成功', () async {
      stub();
      await expectLater(
        service.locate(
          apiKey: 'k' * 32,
          accuracy: LocateAccuracy.high,
          timeout: const Duration(seconds: 20),
          needAddress: true,
        ),
        throwsA(isA<LocationFailure>()),
      );
    });
  });

  group('来源标记', () {
    test('高德那条路径产出的结果标记为高德来源', () {
      final LocationResult result =
          AmapLocationService.parseResult(<Object?, Object?>{
        'latitude': 30.0,
        'longitude': 120.0,
        'accuracy': 8,
        'address': '某地',
      });
      expect(result.source, LocationSource.amap);
      expect(result.source.label, '高德定位');
      // 正常情况下不带降级说明
      expect(result.note, isNull);
    });

    test('copyWith 补地址时保留来源', () {
      final LocationResult amap =
          AmapLocationService.parseResult(<Object?, Object?>{
        'latitude': 30.0,
        'longitude': 120.0,
        'accuracy': 8,
        'address': '',
      });
      expect(amap.address, isNull);

      final LocationResult patched =
          amap.copyWith(address: '系统补的地址');
      expect(patched.address, '系统补的地址');
      expect(patched.source, LocationSource.amap);
      expect(patched.latitude, amap.latitude);
    });

    test('默认来源是系统定位', () {
      const LocationResult result = LocationResult(
        latitude: 30,
        longitude: 120,
        accuracy: 8,
      );
      expect(result.source, LocationSource.system);
    });
  });

  group('地点名优先于街道地址', () {
    test('有 POI 名就用 POI 名，不用「某路某号」', () {
      expect(
        AmapLocationService.pickDisplayAddress(<Object?, Object?>{
          'poiName': '中铁吉盛物流大厦',
          'aoiName': '天河北路产业园',
          'address': '北京市大兴区天河北路5号',
        }),
        '中铁吉盛物流大厦',
      );
    });

    test('没有 POI 名时退到 AOI（园区 / 小区 / 景区）', () {
      expect(
        AmapLocationService.pickDisplayAddress(<Object?, Object?>{
          'poiName': '',
          'aoiName': '天河北路产业园',
          'address': '北京市大兴区天河北路5号',
        }),
        '天河北路产业园',
      );
    });

    test('都没有才用整句地址', () {
      expect(
        AmapLocationService.pickDisplayAddress(<Object?, Object?>{
          'address': '北京市大兴区天河北路5号',
        }),
        '北京市大兴区天河北路5号',
      );
    });

    test('只剩零散字段时自己拼，且不会返回空串', () {
      expect(
        AmapLocationService.pickDisplayAddress(<Object?, Object?>{
          'district': '大兴区',
          'street': '天河北路',
          'streetNum': '5号',
        }),
        '大兴区天河北路5号',
      );
      expect(
        AmapLocationService.pickDisplayAddress(<Object?, Object?>{}),
        isNull,
      );
    });
  });

  group('AmapPlaces', () {
    Map<Object?, Object?> payload({
      String building = '',
      String aoiName = '',
      String formatAddress = '北京市大兴区天河北路5号',
      List<Map<String, Object?>> pois = const <Map<String, Object?>>[],
    }) =>
        <Object?, Object?>{
          'formatAddress': formatAddress,
          'building': building,
          'aoiName': aoiName,
          'pois': pois,
        };

    test('楼宇名最优先', () {
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        building: '中铁吉盛物流大厦',
        aoiName: '某产业园',
        pois: <Map<String, Object?>>[
          <String, Object?>{'title': '永珍超市', 'distance': 30},
        ],
      ));
      expect(places.bestName, '中铁吉盛物流大厦');
    });

    test('没有楼宇和园区时用最近的 POI', () {
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        pois: <Map<String, Object?>>[
          <String, Object?>{'title': '永珍超市', 'distance': 30},
          <String, Object?>{'title': '金羽毛羽球馆', 'distance': 180},
        ],
      ));
      expect(places.bestName, '永珍超市');
      expect(places.places.length, 2);
    });

    test('一个 POI 都没有时退回整句地址', () {
      expect(AmapPlaces.fromMap(payload()).bestName, '北京市大兴区天河北路5号');
      expect(
        AmapPlaces.fromMap(payload(formatAddress: '')).bestName,
        isNull,
      );
    });

    test('标题为空的 POI 会被剔除，不会显示成空条目', () {
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        pois: <Map<String, Object?>>[
          <String, Object?>{'title': '', 'distance': 10},
          <String, Object?>{'title': '永珍超市', 'distance': 30},
        ],
      ));
      expect(places.places.map((AmapPlace p) => p.title), <String>['永珍超市']);
    });

    test('距离按米 / 公里显示', () {
      expect(
        const AmapPlace(title: 'a', distance: 30).distanceText,
        '30 米',
      );
      expect(
        const AmapPlace(title: 'a', distance: 1500).distanceText,
        '1.5 公里',
      );
    });
  });
}
