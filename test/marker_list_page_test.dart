import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/data/app_database.dart';
import 'package:location_marker/data/marker_repository.dart';
import 'package:location_marker/models/location_mark.dart';
import 'package:location_marker/pages/marker_list_page.dart';
import 'package:location_marker/services/media_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 列表页跑在真实的内存数据库上，覆盖 UI 与数据层的接合。
void main() {
  late Database db;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    // widget test 跑在 fake async 下，用不带后台 isolate 的工厂，
    // 否则数据库回调永远等不到，pumpAndSettle 会一直挂着。
    databaseFactory = databaseFactoryFfiNoIsolate;
  });

  setUp(() async {
    db = await databaseFactoryFfiNoIsolate.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: AppDatabase.onCreate,
      ),
    );
    AppDatabase.instance.overrideForTesting(db);
    tempDir = await Directory.systemTemp.createTemp('marker_list_test');
    MediaStore.instance.overrideRootForTesting(tempDir);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> seed() async {
    final DateTime now = DateTime(2026, 5, 18, 16, 20);
    await MarkerRepository.instance.save(LocationMark(
      id: 'a',
      name: '临江公园 · 观景台',
      tags: const <String>['风景'],
      address: '浙江省杭州市西湖区北山街 78 号',
      latitude: 30.259924,
      longitude: 120.146515,
      note: '傍晚六点的光最好',
      createdAt: now,
      updatedAt: now,
    ));
    await MarkerRepository.instance.save(LocationMark(
      id: 'b',
      name: '老陈手工面',
      tags: const <String>['美食'],
      address: '杭州市拱墅区大关路 12 号',
      latitude: 30.313277,
      longitude: 120.145203,
      note: '片儿川 18 块',
      createdAt: now.subtract(const Duration(hours: 2)),
      updatedAt: now,
    ));
  }

  testWidgets('空库时显示空状态', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: MarkerListPage()));
    await tester.pumpAndSettle();

    expect(find.text('还没有标记'), findsOneWidget);
    expect(find.text('还没有记录任何地点'), findsOneWidget);
  });

  testWidgets('渲染数据库里的标记，按时间倒序', (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: MarkerListPage()));
    await tester.pumpAndSettle();

    expect(find.text('临江公园 · 观景台'), findsOneWidget);
    expect(find.text('老陈手工面'), findsOneWidget);
    expect(find.text('共 2 个地点 · 全部保存在本机'), findsOneWidget);
    expect(find.text('浙江省杭州市西湖区北山街 78 号'), findsOneWidget);

    final double firstY = tester.getTopLeft(find.text('临江公园 · 观景台')).dy;
    final double secondY = tester.getTopLeft(find.text('老陈手工面')).dy;
    expect(firstY, lessThan(secondY));
  });

  testWidgets('搜索关键词过滤列表', (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: MarkerListPage()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '手工面');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    expect(find.text('老陈手工面'), findsOneWidget);
    expect(find.text('临江公园 · 观景台'), findsNothing);
  });

  testWidgets('点标签筛选只留该标签的标记', (WidgetTester tester) async {
    await seed();
    await tester.pumpWidget(const MaterialApp(home: MarkerListPage()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(GestureDetector, '美食').first);
    await tester.pumpAndSettle();

    expect(find.text('老陈手工面'), findsOneWidget);
    expect(find.text('临江公园 · 观景台'), findsNothing);
  });
}
