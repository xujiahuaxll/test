import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/data/app_database.dart';
import 'package:location_marker/data/marker_repository.dart';
import 'package:location_marker/models/location_mark.dart';
import 'package:location_marker/services/media_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 在内存库上跑真实 SQL，覆盖增删改查、标签过滤、搜索与级联删除。
void main() {
  late Database db;
  late MarkerRepository repo;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onConfigure: (Database db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: AppDatabase.onCreate,
      ),
    );
    final AppDatabase appDb = AppDatabase.instance;
    appDb.overrideForTesting(db);

    tempDir = await Directory.systemTemp.createTemp('location_marker_test');
    MediaStore.instance.overrideRootForTesting(tempDir);

    repo = MarkerRepository(db: appDb, mediaStore: MediaStore.instance);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  LocationMark buildMark({
    String id = 'm1',
    String name = '临江公园 · 观景台',
    List<String> tags = const <String>['风景', '拍照'],
    String note = '傍晚六点的光最好',
    List<String> photos = const <String>[],
    String? audioPath,
    String? transcript,
  }) {
    final DateTime now = DateTime(2026, 5, 18, 16, 20);
    return LocationMark(
      id: id,
      name: name,
      tags: tags,
      address: '浙江省杭州市西湖区北山街 78 号',
      latitude: 30.259924,
      longitude: 120.146515,
      accuracy: 8,
      note: note,
      photoPaths: photos,
      audioPath: audioPath,
      audioDuration:
          audioPath == null ? null : const Duration(seconds: 42),
      transcript: transcript,
      waveform: audioPath == null ? const <double>[] : <double>[0.4, 0.9, 0.2],
      createdAt: now,
      updatedAt: now,
    );
  }

  test('预置标签在建库时写入', () async {
    expect(await repo.allTags(), AppDatabase.presetTags);
  });

  test('保存后可以按 id 读回，字段完整', () async {
    await repo.save(buildMark(
      photos: <String>['photos/a.jpg', 'photos/b.jpg'],
      audioPath: 'audio/a.m4a',
      transcript: '观景台右侧有一条小路',
    ));

    final LocationMark? loaded = await repo.findById('m1');
    expect(loaded, isNotNull);
    expect(loaded!.name, '临江公园 · 观景台');
    expect(loaded.tags, <String>['风景', '拍照']);
    expect(loaded.photoPaths, <String>['photos/a.jpg', 'photos/b.jpg']);
    expect(loaded.audioDuration, const Duration(seconds: 42));
    expect(loaded.transcript, '观景台右侧有一条小路');
    expect(loaded.waveform, <double>[0.4, 0.9, 0.2]);
    expect(loaded.accuracy, 8);
  });

  test('照片顺序按保存顺序还原', () async {
    await repo.save(buildMark(
      photos: <String>['photos/1.jpg', 'photos/2.jpg', 'photos/3.jpg'],
    ));
    final LocationMark loaded = (await repo.findById('m1'))!;
    expect(loaded.photoPaths,
        <String>['photos/1.jpg', 'photos/2.jpg', 'photos/3.jpg']);
  });

  test('再次保存同一条会覆盖标签与照片，不产生重复', () async {
    await repo.save(buildMark(photos: <String>['photos/a.jpg']));
    await repo.save(buildMark(
      tags: <String>['美食'],
      photos: <String>['photos/b.jpg'],
      name: '改了名字',
    ));

    final LocationMark loaded = (await repo.findById('m1'))!;
    expect(loaded.name, '改了名字');
    expect(loaded.tags, <String>['美食']);
    expect(loaded.photoPaths, <String>['photos/b.jpg']);
    expect(await repo.count(), 1);
  });

  test('按标签过滤', () async {
    await repo.save(buildMark(id: 'a', tags: <String>['风景']));
    await repo.save(buildMark(id: 'b', name: '老陈手工面', tags: <String>['美食']));

    final List<LocationMark> result = await repo.query(tag: '美食');
    expect(result.map((LocationMark m) => m.id), <String>['b']);
  });

  test('关键词搜索命中名称、备注、地址与转写文字', () async {
    await repo.save(buildMark(id: 'a', name: '老陈手工面', note: '片儿川 18 块'));
    await repo.save(buildMark(
      id: 'b',
      name: '街角咖啡',
      note: '靠窗有插座',
      audioPath: 'audio/b.m4a',
      transcript: '手冲耶加雪菲 38 元',
    ));

    expect((await repo.query(keyword: '手工面')).single.id, 'a');
    expect((await repo.query(keyword: '插座')).single.id, 'b');
    expect((await repo.query(keyword: '耶加雪菲')).single.id, 'b');
    expect((await repo.query(keyword: '北山街')).length, 2);
    expect(await repo.query(keyword: '不存在的词'), isEmpty);
  });

  test('列表按创建时间倒序', () async {
    final DateTime base = DateTime(2026, 5, 1);
    for (int i = 0; i < 3; i++) {
      final LocationMark mark = buildMark(id: 'm$i', name: '第 $i 个');
      await repo.save(LocationMark(
        id: mark.id,
        name: mark.name,
        latitude: mark.latitude,
        longitude: mark.longitude,
        createdAt: base.add(Duration(days: i)),
        updatedAt: base.add(Duration(days: i)),
      ));
    }
    final List<LocationMark> list = await repo.query();
    expect(list.map((LocationMark m) => m.id), <String>['m2', 'm1', 'm0']);
  });

  test('自定义标签会被持久化，并在保存标记时自动登记', () async {
    await repo.addTag('夜景');
    expect(await repo.allTags(), contains('夜景'));

    await repo.save(buildMark(tags: <String>['亲子']));
    expect(await repo.allTags(), contains('亲子'));

    // 重复添加不应产生多条
    await repo.addTag('夜景');
    final List<String> tags = await repo.allTags();
    expect(tags.where((String t) => t == '夜景').length, 1);
  });

  test('删除标记会级联清掉标签、照片记录与本地文件', () async {
    final File photo = File('${tempDir.path}/photos/a.jpg')
      ..createSync(recursive: true)
      ..writeAsStringSync('photo');
    final File audio = File('${tempDir.path}/audio/a.m4a')
      ..createSync(recursive: true)
      ..writeAsStringSync('audio');

    final LocationMark mark = buildMark(
      photos: <String>['photos/a.jpg'],
      audioPath: 'audio/a.m4a',
    );
    await repo.save(mark);
    await repo.delete(mark);

    expect(await repo.findById('m1'), isNull);
    expect(await repo.count(), 0);
    expect(photo.existsSync(), isFalse);
    expect(audio.existsSync(), isFalse);

    final List<Map<String, Object?>> tagRows =
        await db.query(AppDatabase.tableMarkerTags);
    final List<Map<String, Object?>> photoRows =
        await db.query(AppDatabase.tableMarkerPhotos);
    expect(tagRows, isEmpty);
    expect(photoRows, isEmpty);
  });

  test('波形与时长为空时也能正常存取', () async {
    await repo.save(buildMark(tags: const <String>[]));
    final LocationMark loaded = (await repo.findById('m1'))!;
    expect(loaded.hasVoice, isFalse);
    expect(loaded.waveform, isEmpty);
    expect(loaded.tags, isEmpty);
  });
}
