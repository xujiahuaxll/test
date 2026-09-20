import '../services/amap_location_service.dart';

/// 给附近地点排个序，让「建筑和站点」排在「店铺」前面。
///
/// 起因：拖动选点时顶上显示的永远是「XX咖啡」「XX便利店」，而用户要的是
/// 高德地图那样的「某某大厦」「某某地铁站B口」。店铺的密度远高于楼宇，
/// 只按距离排，脚下那栋楼永远争不过门口的奶茶店。
///
/// 高德自己是按「距离 × POI 权重」排的，但 Android SDK 不暴露 poiweight
/// 这个数值（只体现在它默认排序的顺序里）。所以这里用公开的分类编码
/// 自己估一份权重——估不出高德的精确结果，但足够把楼和店分开。
class PlaceRanking {
  const PlaceRanking._();

  /// AOI 面积超过这个数（平方米）就不拿来当地点名。
  ///
  /// 大学城、开发区这种整片区域也是一个 AOI，用它当标题等于什么都没说。
  static const double maxAnchorAoiArea = 500000;

  /// 分类权重。数越大越「像个地方」。
  ///
  /// 高德的 typecode 是「大类(2) 中类(2) 小类(2)」定长六位，所以这里从细
  /// 到粗匹配前缀：先看六位的小类，再看四位的中类，最后看两位的大类。
  ///
  /// 分档的依据是「事后回看这条标记时，哪个名字更能让人想起是哪儿」：
  /// 楼栋号和楼宇最高，交通站点次之，商户垫底——但不是零，因为用户
  /// 确实可能就是想标记一家咖啡馆。
  static int weightOf(String typeCode) {
    final String code = typeCode.trim();
    if (code.length < 2) return unknownWeight;

    if (code.length >= 6) {
      switch (code.substring(0, 6)) {
        case '190406': // 楼栋号，「乙27号楼」
          return 100;
        case '190403': // 门址点
          return 90;
      }
    }

    if (code.length >= 4) {
      switch (code.substring(0, 4)) {
        case '1203': // 楼宇：商务写字楼、工业大厦
          return 100;
        case '1505': // 地铁站及出入口
          return 95;
        case '1906': // 标志性建筑物
          return 85;
        case '1501': // 机场
        case '1502': // 火车站
          return 80;
        case '1503': // 长途汽车站
          return 75;
        case '1507': // 公交车站
        case '1201': // 产业园区
          return 70;
        case '1202': // 住宅区
          return 65;
      }
    }

    switch (code.substring(0, 2)) {
      case '11': // 风景名胜
        return 75;
      case '14': // 科教文化服务
        return 70;
      case '10': // 住宿服务
      case '13': // 政府机构及社会团体
      case '12': // 其余商务住宅
      case '15': // 其余交通设施
        return 60;
      case '09': // 医疗保健
        return 55;
      case '19': // 其余地名地址信息
        return 50;
      case '16': // 金融保险
      case '08': // 体育休闲
        return 40;
      case '17': // 公司企业
        return 35;
      case '20': // 公共设施
        return 30;
      case '07': // 生活服务
        return 20;
      case '06': // 购物服务，「XX店」
      case '05': // 餐饮服务，「XX咖啡」
        return 15;
      case '01': // 汽车服务
      case '02': // 汽车销售
      case '03': // 汽车维修
      case '04': // 摩托车服务
        return 10;
      case '18': // 道路附属设施
      case '97': // 室内设施
        return 5;
      case '99': // 虚拟数据
        return 0;
    }
    return unknownWeight;
  }

  /// 没见过的分类给中性值，不高不低。
  ///
  /// 高德以后加新分类时，新东西既不会莫名其妙冲到第一，也不会沉底消失。
  static const int unknownWeight = 30;

  /// 距离要扣多少分。分档而不是线性，是为了让权重压倒距离，
  /// 但拉开足够远之后距离还能翻盘。
  ///
  /// 效果（见单测）：
  /// - 咖啡店 5 米(15) 输给 大厦 400 米(55)——这正是用户要的
  /// - 大厦 400 米(55) 输给 住宅区 5 米(65)——站在小区里不该跳到街对面
  static int distancePenalty(int distance) {
    if (distance <= 50) return 0;
    if (distance <= 150) return 10;
    if (distance <= 300) return 25;
    return 45;
  }

  /// 一个地点的综合得分，越大越靠前。
  static int scoreOf({required int weight, required int distance}) {
    // 距离偶尔会是 0 或负数（同点、或原生侧没算出来），都按「就在脚下」处理
    final int safe = distance < 0 ? 0 : distance;
    return weight - distancePenalty(safe);
  }

  static int scoreFor(AmapPlace place) =>
      scoreOf(weight: weightOf(place.typeCode), distance: place.distance);

  /// 按得分重排。得分相同时近的在前，保证顺序稳定、不会每次刷新都跳。
  static List<AmapPlace> rank(List<AmapPlace> places) {
    final List<AmapPlace> sorted = List<AmapPlace>.of(places);
    sorted.sort((AmapPlace a, AmapPlace b) {
      final int byScore = scoreFor(b).compareTo(scoreFor(a));
      if (byScore != 0) return byScore;
      return a.distance.compareTo(b.distance);
    });
    return List<AmapPlace>.unmodifiable(sorted);
  }

  /// 够格代表「这个位置叫什么」的最低权重。
  ///
  /// 卡在住宅区/产业园区这一档（65）：楼栋号、楼宇、地铁站都在它之上，
  /// 而商户、公司在它之下。低于这档的东西顶多算「附近有什么」，
  /// 不足以当成这个位置本身的名字。
  static const int placeWorthyWeight = 65;

  /// 落点所在的 AOI（园区 / 小区 / 景区）。太大的那种不要。
  static String? anchorAoi(AmapPlaces places) {
    final String aoi = places.aoiName.trim();
    if (aoi.isEmpty) return null;
    final double? area = places.aoiArea;
    if (area != null && area > maxAnchorAoiArea) return null;
    return aoi;
  }

  /// 给这个点取一个名字，对齐高德地图拖动选点的行为。
  ///
  /// 顺序是有讲究的，每一步都踩过坑：
  /// 1. `building` —— 高德自己判定的「坐标落在哪栋楼里」，最权威；
  /// 2. 权重够高的 POI —— 「乙27号楼」比「双河北里小区」具体得多，
  ///    所以它要排在 AOI 前面（AOI 只是个粗粒度的容器）；
  /// 3. AOI —— 楼一级认不出来时，小区名也比店铺名像个地方；
  /// 4. 兜底才轮到商户 —— 荒郊野外只有一家加油站时，它总好过没有。
  ///
  /// 全都没有就返回 null，**不回落到整句地址**：回落的话标题和副标题
  /// 会变成同一句话，白占一行。上层拿到 null 自己用地址当标题。
  static String? bestNameOf(AmapPlaces places) {
    final String building = places.building.trim();
    if (building.isNotEmpty) return building;

    final List<AmapPlace> ranked = rank(places.places);
    final AmapPlace? top = ranked.isEmpty ? null : ranked.first;
    final String topTitle = top?.title.trim() ?? '';

    if (topTitle.isNotEmpty && top!.weight >= placeWorthyWeight) {
      return topTitle;
    }

    final String? aoi = anchorAoi(places);
    if (aoi != null) return aoi;

    return topTitle.isEmpty ? null : topTitle;
  }
}
