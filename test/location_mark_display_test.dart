import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/models/location_mark.dart';

/// 标题 / 副标题的取舍：用户要的是「中铁吉盛」做标题、
/// 「北京市大兴区天河北路5号」做副标题，而不是把街道号当标题。
void main() {
  LocationMark build({String? placeName, String? address}) => LocationMark(
        id: 'm1',
        name: '随便',
        placeName: placeName,
        address: address,
        latitude: 39.686549,
        longitude: 116.319420,
        createdAt: DateTime(2026, 9, 19),
        updatedAt: DateTime(2026, 9, 19),
      );

  test('有地点名时：标题是地点名，副标题是详细地址', () {
    final LocationMark mark = build(
      placeName: '中铁吉盛',
      address: '北京市大兴区天河北路5号',
    );
    expect(mark.displayTitle, '中铁吉盛');
    expect(mark.displaySubtitle, '北京市大兴区天河北路5号');
  });

  test('只有地址时：地址当标题，不重复显示副标题', () {
    final LocationMark mark = build(address: '北京市大兴区天河北路5号');
    expect(mark.displayTitle, '北京市大兴区天河北路5号');
    expect(mark.displaySubtitle, isNull);
  });

  test('旧数据没有 place_name 也能正常显示', () {
    final LocationMark mark = build(placeName: null, address: '某路某号');
    expect(mark.displayTitle, '某路某号');
    expect(mark.displaySubtitle, isNull);
  });

  test('两个都没有时退回坐标，不显示空白', () {
    final LocationMark mark = build();
    expect(mark.displayTitle, contains('39.686549'));
    expect(mark.displaySubtitle, isNull);
  });

  test('有地点名但没地址时不显示空副标题', () {
    final LocationMark mark = build(placeName: '中铁吉盛');
    expect(mark.displayTitle, '中铁吉盛');
    expect(mark.displaySubtitle, isNull);
  });

  test('地点名与地址会一起存进行、一起读回来', () {
    final LocationMark mark = build(
      placeName: '中铁吉盛',
      address: '北京市大兴区天河北路5号',
    );
    final Map<String, Object?> row = mark.toRow();
    expect(row['place_name'], '中铁吉盛');
    expect(row['address'], '北京市大兴区天河北路5号');

    final LocationMark back = LocationMark.fromRow(row, tags: const <String>[]);
    expect(back.placeName, '中铁吉盛');
    expect(back.address, '北京市大兴区天河北路5号');
  });
}
