import 'package:sqflite/sqflite.dart';

import 'app_database.dart';

/// 简单的本地键值设置，跟标记数据一起放在内置数据库里。
class SettingsRepository {
  SettingsRepository({AppDatabase? db}) : _appDb = db ?? AppDatabase.instance;

  static final SettingsRepository instance = SettingsRepository();

  /// 用户是否已同意包含高德隐私政策的隐私声明。
  static const String keyPrivacyAgreed = 'amap_privacy_agreed';

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
}
