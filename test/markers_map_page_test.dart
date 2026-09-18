import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/data/app_database.dart';
import 'package:location_marker/data/marker_repository.dart';
import 'package:location_marker/models/location_mark.dart';
import 'package:location_marker/pages/markers_map_page.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onCreate: AppDatabase.onCreate,
      ),
    );
    AppDatabase.instance.overrideForTesting(db);
  });

  tearDown(() async => db.close());

  test('跨度越大缩放级别越小，且落在高德支持的范围内', () {
    // 两个点几乎重合 -> 用最大级别
    expect(MarkersMapPageState.zoomForSpan(0.0001), 17);
    // 一个城市范围
    final double city = MarkersMapPageState.zoomForSpan(0.05);
    // 跨省范围
    final double province = MarkersMapPageState.zoomForSpan(5);
    expect(city, greaterThan(province));
    expect(province, greaterThanOrEqualTo(3));
    expect(city, lessThanOrEqualTo(17));
    // 极端跨度也要被夹在范围内
    expect(MarkersMapPageState.zoomForSpan(180), greaterThanOrEqualTo(3));
  });

  testWidgets('没有配置高德 Key 时给出明确提示而不是白屏',
      (WidgetTester tester) async {
    final DateTime now = DateTime(2026, 5, 18);
    await MarkerRepository.instance.save(LocationMark(
      id: 'a',
      name: '临江公园 · 观景台',
      latitude: 30.259924,
      longitude: 120.146515,
      createdAt: now,
      updatedAt: now,
    ));

    await tester.pumpWidget(const MaterialApp(home: MarkersMapPage()));
    await tester.pumpAndSettle();

    expect(find.text('地图暂时不可用'), findsOneWidget);
    expect(find.textContaining('还没有配置高德地图 Key'), findsOneWidget);
    expect(find.text('已记录 1 个标记，可以回列表查看'), findsOneWidget);
    expect(find.text('1 个'), findsOneWidget);
  });
}
