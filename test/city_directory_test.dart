import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/amap_location_service.dart';
import 'package:location_marker/services/city_directory.dart';

AmapDistrict node(
  String name,
  String level, {
  String adcode = '',
  List<AmapDistrict> children = const <AmapDistrict>[],
}) {
  return AmapDistrict(
    name: name,
    adcode: adcode,
    level: level,
    children: children,
  );
}

void main() {
  group('城市编码', () {
    test('区一级的编码折到市一级', () {
      // 朝阳区 -> 北京市
      expect(AmapDistrict.cityAdcodeOf('110105'), '110100');
      // 杭州西湖区 -> 杭州市
      expect(AmapDistrict.cityAdcodeOf('330106'), '330100');
    });

    test('拿不到编码时给空串，不要瞎补', () {
      expect(AmapDistrict.cityAdcodeOf(''), '');
      expect(AmapDistrict.cityAdcodeOf('11'), '');
    });
  });

  group('从定位结果推出所在城市', () {
    test('普通地级市用 city 字段', () {
      final AmapDistrict? city = AmapDistrict.fromArea(
        province: '浙江省',
        city: '杭州市',
        adCode: '330106',
      );
      expect(city!.name, '杭州市');
      expect(city.adcode, '330100');
    });

    test('直辖市的 city 是空的，要用省名兜住', () {
      // 不特判的话城市入口会显示成一片空白
      final AmapDistrict? city = AmapDistrict.fromArea(
        province: '北京市',
        city: '',
        adCode: '110105',
      );
      expect(city!.name, '北京市');
      expect(city.adcode, '110100');
    });

    test('什么都没有时返回 null，不要造一个空城市出来', () {
      expect(
        AmapDistrict.fromArea(province: '', city: '', adCode: ''),
        isNull,
      );
    });
  });

  group('把高德返回的区划树整理成省市名单', () {
    final List<AmapDistrict> tree = <AmapDistrict>[
      node('中国', 'country', children: <AmapDistrict>[
        node('浙江省', 'province', adcode: '330000', children: <AmapDistrict>[
          node('杭州市', 'city', adcode: '330100'),
          node('宁波市', 'city', adcode: '330200'),
        ]),
        // 直辖市底下直接挂区，没有 city 一级
        node('北京市', 'province', adcode: '110000', children: <AmapDistrict>[
          node('朝阳区', 'district', adcode: '110105'),
        ]),
      ]),
    ];

    test('省份底下列出城市', () {
      final List<CityGroup> groups = CityDirectory.groupsOf(tree);
      final CityGroup zhejiang =
          groups.firstWhere((CityGroup g) => g.province == '浙江省');
      expect(
        zhejiang.cities.map((AmapDistrict c) => c.name),
        <String>['杭州市', '宁波市'],
      );
    });

    test('直辖市自己顶上城市的位置，不能从名单里消失', () {
      final List<CityGroup> groups = CityDirectory.groupsOf(tree);
      final CityGroup beijing =
          groups.firstWhere((CityGroup g) => g.province == '北京市');
      expect(beijing.cities.single.name, '北京市');
      expect(beijing.cities.single.adcode, '110000');
    });

    test('按城市名搜', () {
      final List<CityGroup> groups = CityDirectory.groupsOf(tree);
      expect(
        CityDirectory.search(groups, '宁波').map((AmapDistrict c) => c.name),
        <String>['宁波市'],
      );
    });

    test('按省名搜会列出省内所有城市', () {
      final List<CityGroup> groups = CityDirectory.groupsOf(tree);
      expect(
        CityDirectory.search(groups, '浙江').map((AmapDistrict c) => c.name),
        <String>['杭州市', '宁波市'],
      );
    });

    test('空关键字不返回结果，免得把整份名单当成搜索命中', () {
      final List<CityGroup> groups = CityDirectory.groupsOf(tree);
      expect(CityDirectory.search(groups, '   '), isEmpty);
    });
  });
}
