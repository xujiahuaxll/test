import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/amap_location_service.dart';
import 'package:location_marker/utils/place_ranking.dart';

AmapPlace place(String title, String typeCode, int distance) =>
    AmapPlace(title: title, typeCode: typeCode, distance: distance);

void main() {
  group('分类权重', () {
    test('楼宇和楼栋号最高——用户要的就是「某某大厦」「乙27号楼」', () {
      expect(PlaceRanking.weightOf('120302'), 100); // 商务写字楼
      expect(PlaceRanking.weightOf('190406'), 100); // 楼栋号
    });

    test('交通站点次之，地铁站高过公交站', () {
      expect(
        PlaceRanking.weightOf('150501'), // 地铁站出入口
        greaterThan(PlaceRanking.weightOf('150700')), // 公交车站
      );
    });

    test('商户垫底，但不是零——用户确实可能就想标记一家咖啡馆', () {
      final int cafe = PlaceRanking.weightOf('050500'); // 咖啡厅
      final int shop = PlaceRanking.weightOf('060400'); // 超市
      expect(cafe, greaterThan(0));
      expect(cafe, lessThan(PlaceRanking.weightOf('120302')));
      expect(shop, lessThan(PlaceRanking.weightOf('150500')));
    });

    test('整条鄙视链：楼宇 > 地铁 > 住宅区 > 公司 > 餐饮 > 汽修', () {
      final List<int> chain = <int>[
        PlaceRanking.weightOf('120302'), // 楼宇
        PlaceRanking.weightOf('150500'), // 地铁站
        PlaceRanking.weightOf('120201'), // 住宅小区
        PlaceRanking.weightOf('170100'), // 公司企业
        PlaceRanking.weightOf('050100'), // 中餐厅
        PlaceRanking.weightOf('030000'), // 汽车维修
      ];
      for (int i = 1; i < chain.length; i++) {
        expect(chain[i], lessThan(chain[i - 1]), reason: '第 $i 档没有比上一档低');
      }
    });

    test('空串、长度不足、没见过的分类都给中性值，不崩也不乱', () {
      expect(PlaceRanking.weightOf(''), PlaceRanking.unknownWeight);
      expect(PlaceRanking.weightOf('1'), PlaceRanking.unknownWeight);
      expect(PlaceRanking.weightOf('  '), PlaceRanking.unknownWeight);
      // 高德以后加新大类时，新东西既不冲第一也不沉底
      expect(PlaceRanking.weightOf('889900'), PlaceRanking.unknownWeight);
    });
  });

  group('距离与权重怎么折中', () {
    int score(String typeCode, int distance) => PlaceRanking.scoreOf(
          weight: PlaceRanking.weightOf(typeCode),
          distance: distance,
        );

    test('脚下的咖啡店输给 400 米外的大厦——这正是用户报的那个问题', () {
      expect(score('050500', 5), lessThan(score('120302', 400)));
    });

    test('但 400 米外的大厦输给脚下的住宅区——站小区里不该跳到街对面', () {
      expect(score('120302', 400), lessThan(score('120201', 5)));
    });

    test('200 米外的地铁站仍然赢过脚边的咖啡店', () {
      expect(score('150500', 200), greaterThan(score('050500', 5)));
    });

    test('距离为 0 或负数都按「就在脚下」算，不产生离谱的分数', () {
      expect(score('120302', 0), score('120302', 10));
      expect(score('120302', -5), score('120302', 0));
    });

    test('同一个地方越远分越低', () {
      expect(score('120302', 500), lessThan(score('120302', 20)));
    });
  });

  group('排序', () {
    test('建筑和站点排到商户前面', () {
      final List<AmapPlace> ranked = PlaceRanking.rank(<AmapPlace>[
        place('幸运咖(双河北里店)', '050500', 8),
        place('7-11', '060400', 15),
        place('双河北里小区-乙27号楼', '190406', 40),
        place('双河北里地铁站B口', '150502', 120),
      ]);
      expect(ranked.first.title, '双河北里小区-乙27号楼');
      expect(ranked[1].title, '双河北里地铁站B口');
      expect(ranked.last.title, anyOf('幸运咖(双河北里店)', '7-11'));
    });

    test('同权重时近的在前', () {
      final List<AmapPlace> ranked = PlaceRanking.rank(<AmapPlace>[
        place('远的店', '050500', 40),
        place('近的店', '050500', 5),
      ]);
      expect(ranked.map((AmapPlace p) => p.title), <String>['近的店', '远的店']);
    });

    test('空列表不出事', () {
      expect(PlaceRanking.rank(const <AmapPlace>[]), isEmpty);
    });

    test('不改动传进来的那个列表', () {
      final List<AmapPlace> input = <AmapPlace>[
        place('店', '050500', 5),
        place('楼', '120302', 90),
      ];
      PlaceRanking.rank(input);
      expect(input.first.title, '店', reason: '原列表被就地排序了');
    });
  });

  group('去重', () {
    test('同名同坐标的只留一条——地铁站可能从周边搜索和子 POI 各回来一次', () {
      final List<AmapPlace> unique = AmapPlace.dedupe(<AmapPlace>[
        const AmapPlace(
            title: '双河北里地铁站', distance: 100, latitude: 39.7, longitude: 116.3),
        const AmapPlace(
            title: '双河北里地铁站', distance: 100, latitude: 39.7, longitude: 116.3),
      ]);
      expect(unique, hasLength(1));
    });

    test('同名但不同坐标要留着——连锁店满街都是同一个名字', () {
      final List<AmapPlace> unique = AmapPlace.dedupe(<AmapPlace>[
        const AmapPlace(
            title: '幸运咖', distance: 10, latitude: 39.7, longitude: 116.3),
        const AmapPlace(
            title: '幸运咖', distance: 80, latitude: 39.8, longitude: 116.4),
      ]);
      expect(unique, hasLength(2));
    });
  });

  group('这个点该叫什么', () {
    AmapPlaces placesOf({
      String building = '',
      String aoiName = '',
      double? aoiArea,
      List<AmapPlace> pois = const <AmapPlace>[],
    }) =>
        AmapPlaces(
          formatAddress: '北京市大兴区天河北路5号',
          building: building,
          aoiName: aoiName,
          aoiArea: aoiArea,
          places: pois,
        );

    test('高德判定的所在楼最权威，压过一切', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          building: '中铁吉盛物流大厦',
          aoiName: '某产业园',
          pois: <AmapPlace>[place('永珍超市', '060400', 3)],
        )),
        '中铁吉盛物流大厦',
      );
    });

    test('楼栋号胜过小区名——小区只是个粗粒度的容器', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          aoiName: '双河北里小区',
          pois: <AmapPlace>[place('双河北里小区-乙27号楼', '190406', 12)],
        )),
        '双河北里小区-乙27号楼',
      );
    });

    test('只有商户时退回小区名，不让「XX咖啡」冒充这个位置', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          aoiName: '双河北里小区',
          pois: <AmapPlace>[place('幸运咖(双河北里店)', '050500', 8)],
        )),
        '双河北里小区',
      );
    });

    test('开发区这种整片 AOI 太粗，不拿来当地点名', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          aoiName: '某某经济技术开发区',
          aoiArea: 8600000,
        )),
        isNull,
      );
    });

    test('面积没超标的 AOI 照用', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          aoiName: '双河北里小区',
          aoiArea: 42000,
        )),
        '双河北里小区',
      );
    });

    test('实在没有别的，商户也好过什么都不显示', () {
      expect(
        PlaceRanking.bestNameOf(placesOf(
          pois: <AmapPlace>[place('中石化加油站', '010100', 60)],
        )),
        '中石化加油站',
      );
    });

    test('全空返回 null，交给上层拿地址当标题', () {
      expect(PlaceRanking.bestNameOf(placesOf()), isNull);
    });
  });
}
