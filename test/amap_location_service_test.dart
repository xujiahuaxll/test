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
}
