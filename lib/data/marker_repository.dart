import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import '../models/location_mark.dart';
import '../services/media_store.dart';
import 'app_database.dart';

/// 标记数据仓储：所有读写都落在本地 SQLite。
/// 用 ChangeNotifier 通知界面刷新，避免引入额外的状态管理依赖。
class MarkerRepository extends ChangeNotifier {
  MarkerRepository({AppDatabase? db, MediaStore? mediaStore})
      : _appDb = db ?? AppDatabase.instance,
        _mediaStore = mediaStore ?? MediaStore.instance;

  static final MarkerRepository instance = MarkerRepository();

  final AppDatabase _appDb;
  final MediaStore _mediaStore;

  Future<Database> get _db => _appDb.database;

  /// 列表查询：keyword 命中名称 / 备注 / 地址 / 转写文字，tag 为标签过滤，
  /// sort 为排序方式（由调用方从设置里取，保持仓储本身无状态）。
  Future<List<LocationMark>> query({
    String? keyword,
    String? tag,
    MarkerSort sort = MarkerSort.newestFirst,
  }) async {
    final Database db = await _db;
    final List<String> where = <String>[];
    final List<Object?> args = <Object?>[];

    final String? kw = keyword?.trim();
    if (kw != null && kw.isNotEmpty) {
      // 字符串字面量必须用单引号：新版 SQLite 不再把双引号当字符串，
      // 会把 "" 解释成标识符并报 no such column。
      where.add("(m.name LIKE ? OR m.note LIKE ? OR IFNULL(m.address, '') "
          "LIKE ? OR IFNULL(m.transcript, '') LIKE ?)");
      final String like = '%$kw%';
      args.addAll(<Object?>[like, like, like, like]);
    }
    if (tag != null && tag.isNotEmpty) {
      where.add('EXISTS (SELECT 1 FROM ${AppDatabase.tableMarkerTags} t '
          'WHERE t.marker_id = m.id AND t.tag = ?)');
      args.add(tag);
    }

    final String sql = 'SELECT m.* FROM ${AppDatabase.tableMarkers} m'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'}'
        ' ORDER BY ${_orderBy(sort)}';

    final List<Map<String, Object?>> rows = await db.rawQuery(sql, args);
    return _hydrate(db, rows);
  }

  /// 按名称排序时再用创建时间兜底，保证同名条目的顺序稳定。
  static String _orderBy(MarkerSort sort) {
    switch (sort) {
      case MarkerSort.newestFirst:
        return 'm.created_at DESC';
      case MarkerSort.oldestFirst:
        return 'm.created_at ASC';
      case MarkerSort.nameAsc:
        return 'm.name COLLATE NOCASE ASC, m.created_at DESC';
    }
  }

  Future<LocationMark?> findById(String id) async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.tableMarkers,
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final List<LocationMark> marks = await _hydrate(db, rows);
    return marks.first;
  }

  Future<int> count() async {
    final Database db = await _db;
    return Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM ${AppDatabase.tableMarkers}'),
        ) ??
        0;
  }

  /// 库里还在引用的媒体相对路径（照片 + 录音），用来找出孤儿文件。
  Future<Set<String>> referencedMediaPaths() async {
    final Database db = await _db;
    final Set<String> paths = <String>{};
    for (final Map<String, Object?> row in await db.query(
      AppDatabase.tableMarkerPhotos,
      columns: <String>['path'],
    )) {
      final Object? path = row['path'];
      if (path is String && path.isNotEmpty) paths.add(path);
    }
    for (final Map<String, Object?> row in await db.query(
      AppDatabase.tableMarkers,
      columns: <String>['audio_path'],
      where: 'audio_path IS NOT NULL',
    )) {
      final Object? path = row['audio_path'];
      if (path is String && path.isNotEmpty) paths.add(path);
    }
    return paths;
  }

  /// 新增或更新一条标记（标签、照片一并覆盖写入）。
  Future<void> save(LocationMark mark) async {
    final Database db = await _db;
    await db.transaction((Transaction txn) async {
      await txn.insert(
        AppDatabase.tableMarkers,
        mark.toRow(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await txn.delete(
        AppDatabase.tableMarkerTags,
        where: 'marker_id = ?',
        whereArgs: <Object?>[mark.id],
      );
      for (int i = 0; i < mark.tags.length; i++) {
        final String tag = mark.tags[i];
        await txn.insert(AppDatabase.tableMarkerTags, <String, Object?>{
          'marker_id': mark.id,
          'tag': tag,
          'position': i,
        });
        await txn.insert(
          AppDatabase.tableTags,
          <String, Object?>{
            'name': tag,
            'created_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      await txn.delete(
        AppDatabase.tableMarkerPhotos,
        where: 'marker_id = ?',
        whereArgs: <Object?>[mark.id],
      );
      for (int i = 0; i < mark.photoPaths.length; i++) {
        await txn.insert(AppDatabase.tableMarkerPhotos, <String, Object?>{
          'marker_id': mark.id,
          'path': mark.photoPaths[i],
          'position': i,
        });
      }
    });
    notifyListeners();
  }

  /// 删除标记，同时清掉它占用的照片与录音文件。
  Future<void> delete(LocationMark mark) async {
    final Database db = await _db;
    await db.delete(
      AppDatabase.tableMarkers,
      where: 'id = ?',
      whereArgs: <Object?>[mark.id],
    );
    for (final String path in mark.photoPaths) {
      await _mediaStore.deleteFile(path);
    }
    final String? audio = mark.audioPath;
    if (audio != null) await _mediaStore.deleteFile(audio);
    notifyListeners();
  }

  /// 所有可选标签（预置 + 用户自定义）。
  Future<List<String>> allTags() async {
    final Database db = await _db;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.tableTags,
      orderBy: 'created_at ASC',
    );
    return rows.map((Map<String, Object?> r) => r['name']! as String).toList();
  }

  Future<void> addTag(String name) async {
    final String tag = name.trim();
    if (tag.isEmpty) return;
    final Database db = await _db;
    await db.insert(
      AppDatabase.tableTags,
      <String, Object?>{
        'name': tag,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    notifyListeners();
  }

  /// 批量补齐标签与照片，避免逐条查询产生 N+1。
  Future<List<LocationMark>> _hydrate(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return <LocationMark>[];

    final List<String> ids =
        rows.map((Map<String, Object?> r) => r['id']! as String).toList();
    final String placeholders = List<String>.filled(ids.length, '?').join(',');

    final List<Map<String, Object?>> tagRows = await db.query(
      AppDatabase.tableMarkerTags,
      where: 'marker_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'position ASC',
    );
    final List<Map<String, Object?>> photoRows = await db.query(
      AppDatabase.tableMarkerPhotos,
      where: 'marker_id IN ($placeholders)',
      whereArgs: ids,
      orderBy: 'position ASC',
    );

    final Map<String, List<String>> tagsById = <String, List<String>>{};
    for (final Map<String, Object?> r in tagRows) {
      tagsById
          .putIfAbsent(r['marker_id']! as String, () => <String>[])
          .add(r['tag']! as String);
    }
    final Map<String, List<String>> photosById = <String, List<String>>{};
    for (final Map<String, Object?> r in photoRows) {
      photosById
          .putIfAbsent(r['marker_id']! as String, () => <String>[])
          .add(r['path']! as String);
    }

    return rows.map((Map<String, Object?> row) {
      final String id = row['id']! as String;
      return LocationMark.fromRow(
        row,
        tags: tagsById[id] ?? const <String>[],
        photoPaths: photosById[id] ?? const <String>[],
      );
    }).toList();
  }
}
