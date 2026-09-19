import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/data/app_database.dart';
import 'package:location_marker/data/settings_repository.dart';
import 'package:location_marker/models/app_settings.dart';
import 'package:location_marker/services/navigation_launcher.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SettingsRepository settings;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: AppDatabase.version,
        onCreate: AppDatabase.onCreate,
      ),
    );
    AppDatabase.instance.overrideForTesting(db);
    settings = SettingsRepository(db: AppDatabase.instance);
  });

  tearDown(() async => db.close());

  test('读不到的键返回默认值', () async {
    expect(await settings.getBool('未设置的键'), isFalse);
    expect(
      await settings.getBool('未设置的键', defaultValue: true),
      isTrue,
    );
    expect(await settings.getString('未设置的键'), isNull);
  });

  test('隐私同意状态可以写入并读回', () async {
    await settings.setBool(SettingsRepository.keyPrivacyAgreed, true);
    expect(
      await settings.getBool(SettingsRepository.keyPrivacyAgreed),
      isTrue,
    );

    await settings.setBool(SettingsRepository.keyPrivacyAgreed, false);
    expect(
      await settings.getBool(SettingsRepository.keyPrivacyAgreed),
      isFalse,
    );
  });

  test('旧版本数据库升级后会补上设置表', () async {
    // 用 v1 的建表逻辑造一个旧库：只建到 tags 表为止
    final Database old = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (Database db, int version) async {
          await db.execute('CREATE TABLE ${AppDatabase.tableTags} '
              '(name TEXT PRIMARY KEY, created_at INTEGER NOT NULL)');
        },
      ),
    );
    await AppDatabase.onUpgrade(old, 1, AppDatabase.version);

    await old.insert(AppDatabase.tableSettings,
        <String, Object?>{'key': 'k', 'value': 'v'});
    final List<Map<String, Object?>> rows =
        await old.query(AppDatabase.tableSettings);
    expect(rows.single['value'], 'v');
    await old.close();
  });

  group('整份配置的读写', () {
    test('没存过任何东西时读出来是默认配置', () async {
      final AppSettings loaded = await settings.loadSettings();
      expect(loaded.toMap(), const AppSettings().toMap());
    });

    test('写入后能完整读回', () async {
      const AppSettings next = AppSettings(
        defaultNavApp: NavApp.tencent,
        travelMode: TravelMode.walking,
        mapKind: MapKind.night,
        showTraffic: true,
        locateAccuracy: LocateAccuracy.balanced,
        locateTimeoutSeconds: 30,
        reverseGeocode: false,
        speechLocale: SpeechLocale.english,
        audioQuality: AudioQuality.saver,
        photoQuality: PhotoQuality.saver,
        markerSort: MarkerSort.oldestFirst,
      );
      await settings.saveSettings(next);

      final AppSettings loaded = await settings.loadSettings();
      expect(loaded.toMap(), next.toMap());
    });

    test('只写真正变了的键，没动的项不会落库', () async {
      const AppSettings before = AppSettings();
      await settings.saveSettings(
        before.copyWith(travelMode: TravelMode.transit),
        previous: before,
      );

      final Map<String, String> stored = await settings.getAll();
      expect(stored.keys, <String>[AppSettings.keyTravelMode]);
      // 没落库的项读出来仍是默认值
      expect(
        (await settings.loadSettings()).photoQuality,
        PhotoQuality.standard,
      );
    });

    test('前后一致时不写库', () async {
      const AppSettings same = AppSettings();
      await settings.saveSettings(same, previous: same);
      expect(await settings.getAll(), isEmpty);
    });

    test('隐私同意状态与配置项共用一张表，互不覆盖', () async {
      await settings.setBool(SettingsRepository.keyPrivacyAgreed, true);
      await settings.saveSettings(
        const AppSettings(mapKind: MapKind.satellite),
      );

      expect(
        await settings.getBool(SettingsRepository.keyPrivacyAgreed),
        isTrue,
      );
      expect((await settings.loadSettings()).mapKind, MapKind.satellite);
    });
  });
}
