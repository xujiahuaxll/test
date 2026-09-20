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
      expect(result.placeName, isNull);
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

  group('地点名与详细地址分开', () {
    test('POI 名做标题，街道地址做副标题', () {
      const Map<Object?, Object?> raw = <Object?, Object?>{
        'poiName': '中铁吉盛物流大厦',
        'aoiName': '天河北路产业园',
        'address': '北京市大兴区天河北路5号',
      };
      expect(AmapLocationService.pickPlaceName(raw), '中铁吉盛物流大厦');
      expect(AmapLocationService.pickFullAddress(raw), '北京市大兴区天河北路5号');
    });

    test('没有 POI 名时退到 AOI（园区 / 小区 / 景区）', () {
      expect(
        AmapLocationService.pickPlaceName(<Object?, Object?>{
          'poiName': '',
          'aoiName': '天河北路产业园',
        }),
        '天河北路产业园',
      );
    });

    test('两个都没有时地点名为空，界面会拿地址当标题', () {
      expect(
        AmapLocationService.pickPlaceName(<Object?, Object?>{
          'address': '北京市大兴区天河北路5号',
        }),
        isNull,
      );
    });

    test('地址缺失时用零散字段拼一条，全空返回 null', () {
      expect(
        AmapLocationService.pickFullAddress(<Object?, Object?>{
          'district': '大兴区',
          'street': '天河北路',
          'streetNum': '5号',
        }),
        '大兴区天河北路5号',
      );
      expect(
        AmapLocationService.pickFullAddress(<Object?, Object?>{}),
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

    test('没有楼宇时用楼栋号，它比园区名更具体', () {
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        aoiName: '双河北里小区',
        pois: <Map<String, Object?>>[
          // 190406 = 楼栋号
          <String, Object?>{
            'title': '双河北里小区-乙27号楼',
            'distance': 12,
            'typeCode': '190406',
          },
          // 080000 = 体育休闲，权重不够格代表这个位置
          <String, Object?>{
            'title': '金羽毛羽球馆',
            'distance': 180,
            'typeCode': '080300',
          },
        ],
      ));
      expect(places.bestName, '双河北里小区-乙27号楼');
    });

    test('只有商户时用园区名，不能让「XX咖啡」冒充这个位置', () {
      // 这正是用户报的问题：拖到小区里，顶上显示的却是门口的咖啡店
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        aoiName: '双河北里小区',
        pois: <Map<String, Object?>>[
          <String, Object?>{
            'title': '幸运咖(双河北里店)',
            'distance': 8,
            'typeCode': '050500',
          },
        ],
      ));
      expect(places.bestName, '双河北里小区');
    });

    test('连园区都没有时，商户也好过什么都不显示', () {
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        pois: <Map<String, Object?>>[
          <String, Object?>{
            'title': '中石化加油站',
            'distance': 60,
            'typeCode': '010100',
          },
        ],
      ));
      expect(places.bestName, '中石化加油站');
    });

    test('AOI 太大就不拿来当地点名', () {
      // 「某某经济开发区」整片几平方公里，用它当标题等于什么都没说
      final AmapPlaces places = AmapPlaces.fromMap(<Object?, Object?>{
        'formatAddress': '某市某区某路',
        'aoiName': '某某经济技术开发区',
        'aoiArea': 8600000.0,
        'pois': <Map<String, Object?>>[],
      });
      expect(places.bestName, isNull);
    });

    test('只有园区名时用园区名', () {
      expect(
        AmapPlaces.fromMap(payload(aoiName: '双河北里小区')).bestName,
        '双河北里小区',
      );
    });

    test('都没有时返回 null，不能回落到整句地址', () {
      // 回落的话标题和副标题会是同一句话，白占一行
      final AmapPlaces places = AmapPlaces.fromMap(payload(
        formatAddress: '北京市大兴区观音寺街道双河北里三巷',
      ));
      expect(places.bestName, isNull);
      expect(places.formatAddress, '北京市大兴区观音寺街道双河北里三巷');
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

  group('输入提示与周边搜索', () {
    const String key = 'k';

    test('关键词为空时不发请求，直接返回空', () async {
      bool called = false;
      stub(payload: null, onCall: (MethodCall _) => called = true);
      final List<AmapPlace> tips =
          await service.inputTips(apiKey: key, keyword: '   ');
      expect(tips, isEmpty);
      expect(called, isFalse, reason: '空关键词不该打扰原生侧');
    });

    test('选了城市就把范围收进城里，不然搜「人民医院」会出来全国的', () async {
      MethodCall? seen;
      stub(payload: null, onCall: (MethodCall call) => seen = call);
      await service.inputTips(
        apiKey: key,
        keyword: '人民医院',
        city: '110100',
        cityLimit: true,
      );
      final Map<Object?, Object?> args =
          seen!.arguments as Map<Object?, Object?>;
      expect(args['city'], '110100');
      expect(args['cityLimit'], isTrue);
    });

    test('没给城市时不限定，否则会一条都搜不到', () async {
      MethodCall? seen;
      stub(payload: null, onCall: (MethodCall call) => seen = call);
      // 就算调用方把 cityLimit 打开，没有城市可限也必须传 false
      await service.inputTips(apiKey: key, keyword: '人民医院', cityLimit: true);
      final Map<Object?, Object?> args =
          seen!.arguments as Map<Object?, Object?>;
      expect(args['city'], '');
      expect(args['cityLimit'], isFalse);
    });

    test('周边搜索把坐标、半径、关键词如实传下去', () async {
      MethodCall? seen;
      stub(payload: null, onCall: (MethodCall call) => seen = call);
      await service.nearbyPois(
        apiKey: key,
        latitude: 39.738,
        longitude: 116.341,
        radius: 500,
        keyword: '号楼',
      );
      expect(seen!.method, 'nearbyPois');
      final Map<Object?, Object?> args =
          seen!.arguments as Map<Object?, Object?>;
      expect(args['latitude'], 39.738);
      expect(args['radius'], 500);
      expect(args['keyword'], '号楼');
    });

    test('逆地理编码会声明坐标系，避免多转一道', () async {
      MethodCall? seen;
      stub(
        payload: <Object?, Object?>{'formatAddress': '某地', 'pois': <Object?>[]},
        onCall: (MethodCall call) => seen = call,
      );
      await service.nearbyPlaces(
        apiKey: key,
        latitude: 39.738,
        longitude: 116.341,
        gcj: true,
      );
      expect((seen!.arguments as Map<Object?, Object?>)['gcj'], isTrue);
    });

    test('结果带回坐标，选中后才能把图钉挪过去', () {
      final List<AmapPlace> places = AmapPlace.listFrom(<Object?>[
        <Object?, Object?>{
          'title': '双河北里乙27号楼',
          'snippet': '北京市大兴区观音寺街道',
          'distance': 18,
          'latitude': 39.7380,
          'longitude': 116.3416,
        },
      ]);
      expect(places.single.title, '双河北里乙27号楼');
      expect(places.single.hasPoint, isTrue);
      expect(places.single.latitude, 39.7380);
    });

    test('没有坐标的条目标记为不可跳转，但不丢弃', () {
      final List<AmapPlace> places = AmapPlace.listFrom(<Object?>[
        <Object?, Object?>{'title': '某公交线路', 'distance': 0},
      ]);
      expect(places.single.hasPoint, isFalse);
    });

    test('标题为空的条目会被剔除', () {
      final List<AmapPlace> places = AmapPlace.listFrom(<Object?>[
        <Object?, Object?>{'title': '', 'distance': 0},
        <Object?, Object?>{'title': '甲28号楼', 'distance': 30},
      ]);
      expect(places.map((AmapPlace p) => p.title), <String>['甲28号楼']);
    });

    test('逆地理编码带回所在城市，直辖市用省名兜住', () async {
      stub(payload: <Object?, Object?>{
        'formatAddress': '北京市大兴区天河北路5号',
        'province': '北京市',
        'city': '',
        'adCode': '110115',
        'pois': <Object?>[],
      });
      final AmapPlaces places = await service.nearbyPlaces(
        apiKey: key,
        latitude: 39.738,
        longitude: 116.341,
      );
      expect(places.cityDistrict!.name, '北京市');
      expect(places.cityDistrict!.adcode, '110100');
    });

    test('原生报错时带上错误码，不吞掉', () async {
      stub(error: PlatformException(code: 'tips_1002', message: ''));
      await expectLater(
        service.inputTips(apiKey: key, keyword: '双河北里'),
        throwsA(
          isA<LocationFailure>().having(
            (LocationFailure f) => f.message,
            'message',
            contains('tips_1002'),
          ),
        ),
      );
    });
  });
}
