import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/pages/pick_location_page.dart';
import 'package:location_marker/utils/coordinate.dart';

/// 选点页的相机回调判定。
///
/// 程序化移动和用户拖动触发的是同一个 onCameraMoveEnd。分不出来的话，
/// 「搜索选中 -> 图钉挪过去」会被当成一次拖动，把刚选好的地点名清掉——
/// 表现就是第一次搜索选中后底部没变，再搜一次才好。
void main() {
  const LatLngPair target = LatLngPair(39.738054, 116.340898);

  test('停在目标点上：认定是自己挪的，保留已选中的地点名', () {
    expect(PickLocationPageState.isOwnMove(target, target), isTrue);
  });

  test('几米的落点误差仍算自己挪的', () {
    // 约 5 米
    const LatLngPair nearby = LatLngPair(39.738099, 116.340898);
    expect(
      CoordinateConverter.distanceInMeters(
        nearby.latitude,
        nearby.longitude,
        target.latitude,
        target.longitude,
      ),
      lessThan(20),
    );
    expect(PickLocationPageState.isOwnMove(nearby, target), isTrue);
  });

  test('拖远了就是用户拖的，要重新解析', () {
    // 约 100 米开外
    const LatLngPair dragged = LatLngPair(39.739000, 116.340898);
    expect(
      CoordinateConverter.distanceInMeters(
        dragged.latitude,
        dragged.longitude,
        target.latitude,
        target.longitude,
      ),
      greaterThan(20),
    );
    expect(PickLocationPageState.isOwnMove(dragged, target), isFalse);
  });

  test('没有待匹配的目标时一律当成用户拖动', () {
    expect(PickLocationPageState.isOwnMove(target, null), isFalse);
  });

  test('用距离而不是布尔开关，回调丢了也能自愈', () {
    // 假设某次程序化移动没有回调，目标点一直挂着；
    // 用户下一次拖到别处时，距离对不上，照样被当成拖动处理。
    const LatLngPair staleTarget = LatLngPair(39.700000, 116.300000);
    const LatLngPair userDragged = LatLngPair(39.750000, 116.350000);
    expect(PickLocationPageState.isOwnMove(userDragged, staleTarget), isFalse);
  });
}
