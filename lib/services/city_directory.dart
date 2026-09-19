import 'amap_location_service.dart';
import 'location_service.dart';

/// 全国城市名单。
///
/// 名单不写在代码里：行政区划会调整，写死就得跟着发版，漏一个城市用户
/// 只能干等。直接问高德要，它本来就维护着这份数据。
///
/// 一次请求把「省 -> 市」整棵树拿回来，之后翻省份、搜城市都在本地做，
/// 不会打一个字就发一次网络请求。
class CityDirectory {
  CityDirectory._();

  static final CityDirectory instance = CityDirectory._();

  List<CityGroup>? _cached;
  Future<List<CityGroup>>? _inFlight;

  /// 已经取回来的名单，没取过时为 null。
  List<CityGroup>? get cached => _cached;

  /// 取全国城市名单。并发调用共用同一次请求。
  Future<List<CityGroup>> load(String apiKey) {
    final List<CityGroup>? done = _cached;
    if (done != null) return Future<List<CityGroup>>.value(done);
    return _inFlight ??= _fetch(apiKey);
  }

  Future<List<CityGroup>> _fetch(String apiKey) async {
    try {
      final List<AmapDistrict> tree =
          await AmapLocationService.instance.districts(
        apiKey: apiKey,
        keyword: '中国',
        level: 'country',
        subDistrict: 2,
      );
      final List<CityGroup> groups = groupsOf(tree);
      if (groups.isNotEmpty) _cached = groups;
      return groups;
    } on LocationFailure {
      rethrow;
    } finally {
      _inFlight = null;
    }
  }

  /// 把高德返回的树整理成「省份 + 省内城市」。
  ///
  /// 直辖市在树里只有省一级、底下直接挂区，所以省本身要顶上城市的位置，
  /// 否则北京上海就从名单里消失了。
  static List<CityGroup> groupsOf(List<AmapDistrict> tree) {
    final List<AmapDistrict> provinces = <AmapDistrict>[];
    for (final AmapDistrict node in tree) {
      if (node.level == 'country') {
        provinces.addAll(node.children);
      } else {
        provinces.add(node);
      }
    }

    final List<CityGroup> groups = <CityGroup>[];
    for (final AmapDistrict province in provinces) {
      final List<AmapDistrict> cities = province.children
          .where((AmapDistrict c) => c.level == 'city')
          .toList(growable: false);
      groups.add(
        CityGroup(
          province: province.name,
          cities: cities.isEmpty ? <AmapDistrict>[province] : cities,
        ),
      );
    }
    return groups.where((CityGroup g) => g.cities.isNotEmpty).toList();
  }

  /// 按关键字筛城市。省名也能搜到，输「广东」会列出省内所有城市。
  static List<AmapDistrict> search(List<CityGroup> groups, String keyword) {
    final String needle = keyword.trim();
    if (needle.isEmpty) return const <AmapDistrict>[];
    final List<AmapDistrict> hits = <AmapDistrict>[];
    for (final CityGroup group in groups) {
      final bool byProvince = group.province.contains(needle);
      for (final AmapDistrict city in group.cities) {
        if (byProvince || city.name.contains(needle)) hits.add(city);
      }
    }
    return hits;
  }
}

/// 一个省份和它底下的城市。
class CityGroup {
  const CityGroup({required this.province, required this.cities});

  final String province;
  final List<AmapDistrict> cities;
}
