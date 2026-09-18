import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 内置 SQLite 数据库。整个 App 的数据都落在本地，不连任何服务端。
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const String fileName = 'location_marker.db';
  static const int version = 1;

  static const String tableMarkers = 'markers';
  static const String tableMarkerTags = 'marker_tags';
  static const String tableMarkerPhotos = 'marker_photos';
  static const String tableTags = 'tags';

  /// 预置标签，首次建库时写入。
  static const List<String> presetTags = <String>[
    '美食',
    '风景',
    '咖啡',
    '打卡',
    '露营',
    '拍照',
    '工作',
    '待办',
  ];

  Database? _db;

  /// 测试里可以注入 ffi 打开的内存库。
  // ignore: use_setters_to_change_properties
  void overrideForTesting(Database db) => _db = db;

  Future<Database> get database async {
    final Database? existing = _db;
    if (existing != null) return existing;

    final String dir = await getDatabasesPath();
    final Database db = await openDatabase(
      p.join(dir, fileName),
      version: version,
      onConfigure: (Database db) =>
          db.execute('PRAGMA foreign_keys = ON'),
      onCreate: onCreate,
    );
    _db = db;
    return db;
  }

  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  /// 建表逻辑单独抽出来，单元测试可以直接对内存库执行。
  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $tableMarkers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        note TEXT NOT NULL DEFAULT '',
        address TEXT,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        accuracy REAL,
        audio_path TEXT,
        audio_duration_ms INTEGER,
        transcript TEXT,
        waveform TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMarkerTags (
        marker_id TEXT NOT NULL,
        tag TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        PRIMARY KEY (marker_id, tag),
        FOREIGN KEY (marker_id) REFERENCES $tableMarkers (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableMarkerPhotos (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        marker_id TEXT NOT NULL,
        path TEXT NOT NULL,
        position INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (marker_id) REFERENCES $tableMarkers (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
      CREATE TABLE $tableTags (
        name TEXT PRIMARY KEY,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute(
      'CREATE INDEX idx_markers_created_at ON $tableMarkers (created_at DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_marker_tags_tag ON $tableMarkerTags (tag)',
    );

    final Batch batch = db.batch();
    final int now = DateTime.now().millisecondsSinceEpoch;
    for (final String tag in presetTags) {
      batch.insert(tableTags, <String, Object?>{
        'name': tag,
        'created_at': now,
      });
    }
    await batch.commit(noResult: true);
  }
}
