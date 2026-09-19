import 'package:sqflite/sqflite.dart';

import '../models/app_settings.dart';
import 'app_database.dart';

/// 简单的本地键值设置，跟标记数据一起放在内置数据库里。
class SettingsRepository {
  SettingsRepository({AppDatabase? db}) : _appDb = db ?? AppDatabase.instance;

  static final SettingsRepository instance = SettingsRepository();

  /// 用户是否已同意包含高德隐私政策的隐私声明。
  static const String keyPrivacyAgreed = 'amap_privacy_agreed';

  /// 用户自己填的高德 Key，两个平台分开存。
  /// 不放进 AppSettings：「恢复默认设置」不应该把用户的 Key 也清掉。
  static const String keyAmapAndroidKey = 'amap_android_key';
  static const String keyAmapIosKey = 'amap_ios_key';

  final AppDatabase _appDb;

  Future<String?> getString(String key) async {
    final Database db = await _appDb.database;
    final List<Map<String, Object?>> rows = await db.query(
      AppDatabase.tableSettings,
      where: 'key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setString(String key, String value) async {
    final Database db = await _appDb.database;
    await db.insert(
      AppDatabase.tableSettings,
      <String, Object?>{'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<bool> getBool(String key, {bool defaultValue = false}) async {
    final String? raw = await getString(key);
    if (raw == null) return defaultValue;
    return raw == 'true';
  }

  Future<void> setBool(String key, bool value) =>
      setString(key, value ? 'true' : 'false');

  /// 一次性读出整张设置表。
  Future<Map<String, String>> getAll() async {
    final Database db = await _appDb.database;
    final List<Map<String, Object?>> rows =
        await db.query(AppDatabase.tableSettings);
    return <String, String>{
      for (final Map<String, Object?> row in rows)
        row['key'] as String: row['value'] as String,
    };
  }

  /// 读回用户的全部配置项；没存过的键走默认值。
  Future<AppSettings> loadSettings() async =>
      AppSettings.fromMap(await getAll());

  /// 落库改动。只写真正变了的键，一个事务里写完。
  Future<void> saveSettings(AppSettings next, {AppSettings? previous}) async {
    final Map<String, String> nextMap = next.toMap();
    final Map<String, String>? prevMap = previous?.toMap();
    final Map<String, String> changed = <String, String>{
      for (final MapEntry<String, String> entry in nextMap.entries)
        if (prevMap == null || prevMap[entry.key] != entry.value)
          entry.key: entry.value,
    };
    if (changed.isEmpty) return;

    final Database db = await _appDb.database;
    await db.transaction((Transaction txn) async {
      for (final MapEntry<String, String> entry in changed.entries) {
        await txn.insert(
          AppDatabase.tableSettings,
          <String, Object?>{'key': entry.key, 'value': entry.value},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }
}
