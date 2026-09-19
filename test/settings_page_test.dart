import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/data/app_database.dart';
import 'package:location_marker/data/settings_repository.dart';
import 'package:location_marker/models/app_settings.dart';
import 'package:location_marker/pages/settings_page.dart';
import 'package:flutter/services.dart';
import 'package:location_marker/config/amap_config.dart';
import 'package:location_marker/services/amap_location_service.dart';
import 'package:location_marker/services/amap_runtime.dart';
import 'package:location_marker/services/media_store.dart';
import 'package:location_marker/services/settings_controller.dart';
import 'package:location_marker/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// 设置页跑在真实的内存数据库上：改一项要真的落库，重新读还在。
void main() {
  late Database db;
  late Directory tempDir;

  setUpAll(() {
    sqfliteFfiInit();
    // widget test 在 fake async 下跑，必须用不带后台 isolate 的工厂。
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
    tempDir = await Directory.systemTemp.createTemp('settings_page_test');
    MediaStore.instance.overrideRootForTesting(tempDir);
    // 每个用例都从空库读一次，把上一个用例留下的状态冲掉。
    await SettingsController.instance.load();
    await AmapRuntime.instance.restore();
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 设置项比默认测试窗口高得多，ListView 只会建可见的那几行。
  /// 把视口撑高让整页一次渲染完，省掉每个断言前的滚动。
  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light(), home: const SettingsPage()),
    );
    await tester.pumpAndSettle();
  }

  /// 点开某一行的单选面板，再选中其中一个选项。
  Future<void> choose(
    WidgetTester tester,
    String row,
    String option,
  ) async {
    await tester.tap(find.text(row));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('各组配置项都渲染出来，并显示当前值', (WidgetTester tester) async {
    await pumpPage(tester);

    for (final String group in <String>['导航', '地图', '定位', '备注与录音', '照片']) {
      expect(find.text(group), findsOneWidget, reason: '缺少「$group」分组');
    }

    expect(find.text('默认导航应用'), findsOneWidget);
    // 默认是「每次询问」
    expect(find.text('每次询问'), findsOneWidget);
    expect(find.text('驾车'), findsOneWidget);
  });

  testWidgets('改出行方式会落库，重新读还在', (WidgetTester tester) async {
    await pumpPage(tester);
    await choose(tester, '出行方式', '步行');

    expect(SettingsController.instance.value.travelMode, TravelMode.walking);

    final AppSettings reloaded =
        await SettingsRepository(db: AppDatabase.instance).loadSettings();
    expect(reloaded.travelMode, TravelMode.walking);
    // 界面上的当前值也跟着变了
    expect(find.text('步行'), findsOneWidget);
  });

  testWidgets('改默认导航应用后不再是「每次询问」', (WidgetTester tester) async {
    await pumpPage(tester);
    await choose(tester, '默认导航应用', '高德地图');

    expect(SettingsController.instance.value.defaultNavApp?.label, '高德地图');
    expect(find.text('每次询问'), findsNothing);
  });

  testWidgets('开关项可以切换并落库', (WidgetTester tester) async {
    await pumpPage(tester);
    expect(SettingsController.instance.value.showTraffic, isFalse);

    await tester.tap(
      find.descendant(
        of: find
            .ancestor(of: find.text('实时路况'), matching: find.byType(Row))
            .first,
        matching: find.byType(Switch),
      ),
    );
    await tester.pumpAndSettle();

    expect(SettingsController.instance.value.showTraffic, isTrue);
    final AppSettings reloaded =
        await SettingsRepository(db: AppDatabase.instance).loadSettings();
    expect(reloaded.showTraffic, isTrue);
  });

  testWidgets('恢复默认设置会把改过的项清回去', (WidgetTester tester) async {
    await SettingsController.instance.update(
      const AppSettings(
        travelMode: TravelMode.transit,
        markerSort: MarkerSort.nameAsc,
      ),
    );
    await pumpPage(tester);
    expect(find.text('公交'), findsOneWidget);

    await tester.tap(find.text('恢复默认设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('恢复'));
    await tester.pumpAndSettle();

    expect(SettingsController.instance.value.toMap(),
        const AppSettings().toMap());
    final AppSettings reloaded =
        await SettingsRepository(db: AppDatabase.instance).loadSettings();
    expect(reloaded.toMap(), const AppSettings().toMap());
  });

  testWidgets('没有孤儿文件时清理给出提示', (WidgetTester tester) async {
    await pumpPage(tester);

    await tester.tap(find.text('清理未引用文件'));
    await tester.pump();

    // 清理要读真实文件系统和数据库，fake async 不会推进这些 Future，
    // 得放到 runAsync 里让真实事件循环跑完，否则 loading 一直转。
    // 留出几轮，避免机器慢的时候刚好差一点。
    for (int i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      if (find.text('没有需要清理的文件').evaluate().isNotEmpty) break;
    }

    expect(find.text('没有需要清理的文件'), findsOneWidget);
  });

  group('高德 Key', () {
    const String key = '0123456789abcdef0123456789abcdef';

    test('没填 Key 时地图不可用', () {
      expect(AmapRuntime.instance.hasKey, isFalse);
      expect(AmapRuntime.instance.mapReady, isFalse);
    });

    testWidgets('未配置时这一行提示去填自己的 Key', (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('高德地图 Key'), findsOneWidget);
      expect(find.text('未配置'), findsOneWidget);
      // 隐私开关在没有 Key 时是置灰的
      final Switch privacySwitch = tester.widget<Switch>(
        find.descendant(
          of: find
              .ancestor(
                of: find.text('同意高德隐私声明'),
                matching: find.byType(Row),
              )
              .first,
          matching: find.byType(Switch),
        ),
      );
      expect(privacySwitch.onChanged, isNull);
    });

    testWidgets('填一个合法 Key 会落库并生效', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('高德地图 Key'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), key);
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      // 刚填完 Key 还没同意过隐私声明，会补问一次
      expect(find.text('隐私声明'), findsOneWidget);
      await tester.tap(find.text('同意'));
      await tester.pumpAndSettle();

      expect(AmapRuntime.instance.userKey.value, key);
      expect(AmapRuntime.instance.effectiveKey, key);
      expect(AmapRuntime.instance.hasKey, isTrue);
      expect(AmapRuntime.instance.usingBuildKey, isFalse);
      expect(AmapRuntime.instance.mapReady, isTrue);

      // 真的写进了数据库：重新读一次还在
      final SettingsRepository repo =
          SettingsRepository(db: AppDatabase.instance);
      expect(
        await repo.getString(SettingsRepository.keyAmapAndroidKey),
        key,
      );

      // 界面上这一行跟着变成「已填」，并只露出首尾
      expect(find.text('已填'), findsOneWidget);
      expect(
        find.text('正在用你自己填的 Key（${AmapConfig.mask(key)}）'),
        findsOneWidget,
      );
    });

    testWidgets('格式少见的 Key 只提示不拦截，照样能存', (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('高德地图 Key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'my-unusual-key-2026');
      await tester.pumpAndSettle();

      // 给提示，但不挡着保存——能不能用由高德判定，不该由我的正则决定
      expect(
        find.textContaining('看着不像常见的 32 位 Key'),
        findsOneWidget,
      );

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      // 没同意过隐私声明，保存后会补问一次
      if (find.text('隐私声明').evaluate().isNotEmpty) {
        await tester.tap(find.text('同意'));
        await tester.pumpAndSettle();
      }

      expect(AmapRuntime.instance.userKey.value, 'my-unusual-key-2026');

      final SettingsRepository repo =
          SettingsRepository(db: AppDatabase.instance);
      expect(
        await repo.getString(SettingsRepository.keyAmapAndroidKey),
        'my-unusual-key-2026',
      );
    });

    testWidgets('清空并保存会撤掉自己的 Key', (WidgetTester tester) async {
      await AmapRuntime.instance.setUserKey(key);
      await pumpPage(tester);
      expect(find.text('已填'), findsOneWidget);

      await tester.tap(find.text('高德地图 Key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(AmapRuntime.instance.userKey.value, isEmpty);
      expect(AmapRuntime.instance.hasKey, isFalse);
      expect(find.text('未配置'), findsOneWidget);
    });

    testWidgets('取消不会改动已存的 Key', (WidgetTester tester) async {
      await AmapRuntime.instance.setUserKey(key);
      await pumpPage(tester);

      await tester.tap(find.text('高德地图 Key'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ffffffffffffffffffffffffffffffff');
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(AmapRuntime.instance.userKey.value, key);
    });

    testWidgets('恢复默认设置不会清掉用户的 Key', (WidgetTester tester) async {
      await AmapRuntime.instance.setUserKey(key);
      await pumpPage(tester);

      await tester.tap(find.text('恢复默认设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复'));
      await tester.pumpAndSettle();

      expect(AmapRuntime.instance.userKey.value, key);
      final SettingsRepository repo =
          SettingsRepository(db: AppDatabase.instance);
      expect(
        await repo.getString(SettingsRepository.keyAmapAndroidKey),
        key,
      );
    });
  });

  group('包名与签名 SHA1', () {
    const String sha1 = '22:D4:66:50:CD:88:73:91:02:C6:13:14:42:40:2E:51';
    const String pkg = 'com.example.location_marker';

    /// 原生通道打桩：只回应 appSignature，其它方法返回 null。
    void stubSignature({Map<Object?, Object?>? payload}) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AmapLocationService.channel,
              (MethodCall call) async {
        if (call.method == 'appSignature') return payload;
        return null;
      });
    }

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(AmapLocationService.channel, null);
    });

    testWidgets('读到后显示包名与 SHA1，供登记 Key 用', (WidgetTester tester) async {
      stubSignature(payload: <Object?, Object?>{
        'packageName': pkg,
        'sha1': sha1,
      });
      await pumpPage(tester);

      expect(find.text('应用包名'), findsOneWidget);
      expect(find.text(pkg), findsOneWidget);
      expect(find.text('签名 SHA1'), findsOneWidget);
      expect(find.text(sha1), findsOneWidget);
    });

    testWidgets('点一下复制到剪贴板', (WidgetTester tester) async {
      stubSignature(payload: <Object?, Object?>{
        'packageName': pkg,
        'sha1': sha1,
      });

      String? copied;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform,
              (MethodCall call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await pumpPage(tester);
      await tester.tap(find.text('签名 SHA1'));
      await tester.pumpAndSettle();

      expect(copied, sha1);
      expect(find.text('签名 SHA1已复制'), findsOneWidget);
    });

    testWidgets('读不到签名时显示占位，不留空白也不崩', (WidgetTester tester) async {
      stubSignature();
      await pumpPage(tester);

      expect(find.text('签名 SHA1'), findsOneWidget);
      // 两行各一个占位
      expect(find.text('读取中…'), findsNWidgets(2));
    });
  });
}
