import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/upgrade_service.dart';

const AppVersion kCurrent = AppVersion(name: '1.0.0', code: 1);

UpgradeInfo parse(Map<String, Object?> json, {AppVersion? current}) =>
    UpgradeInfo.fromJson(json, current: current ?? kCurrent);

void main() {
  group('版本号比较', () {
    test('逐段比数值，不是比字符串', () {
      // 按字符串比的话 '1.9' > '1.10'，这是最常见的踩坑
      expect(UpgradeService.compareVersion('1.10.0', '1.9.0'), greaterThan(0));
      expect(UpgradeService.compareVersion('2.0.0', '1.99.99'), greaterThan(0));
    });

    test('段数不等时短的补 0', () {
      expect(UpgradeService.compareVersion('1.2', '1.2.0'), 0);
      expect(UpgradeService.compareVersion('1.2.1', '1.2'), greaterThan(0));
    });

    test('开头的 v 不算数', () {
      expect(UpgradeService.compareVersion('v1.2.0', '1.2.0'), 0);
    });

    test('带后缀的段退回按字符串比，但不能抛异常', () {
      expect(
        () => UpgradeService.compareVersion('1.2.0-beta', '1.2.0'),
        returnsNormally,
      );
      expect(UpgradeService.compareVersion('1.2.0', '1.2.0'), 0);
    });

    test('空串当成 0，不崩', () {
      expect(UpgradeService.compareVersion('', '0'), 0);
      expect(UpgradeService.compareVersion('1.0.0', ''), greaterThan(0));
    });
  });

  group('拼检查地址', () {
    test('带上版本、构建号与平台', () {
      final Uri uri = UpgradeService.buildCheckUri(
        'https://example.com/latest',
        kCurrent,
      );
      expect(uri.queryParameters['version'], '1.0.0');
      expect(uri.queryParameters['build'], '1');
      expect(uri.queryParameters['platform'], 'android');
    });

    test('地址自带的查询参数要保留，不能被冲掉', () {
      // 用户可能在地址里带了自己的 token
      final Uri uri = UpgradeService.buildCheckUri(
        'https://example.com/latest?token=abc',
        kCurrent,
      );
      expect(uri.queryParameters['token'], 'abc');
      expect(uri.queryParameters['version'], '1.0.0');
    });
  });

  group('解析服务端答复', () {
    test('versionCode 比当前大就是有更新', () {
      final UpgradeInfo info = parse(<String, Object?>{
        'version': '1.1.0',
        'versionCode': 2,
        'url': 'https://example.com/a.apk',
      });
      expect(info.hasUpdate, isTrue);
      expect(info.version, '1.1.0');
      expect(info.versionCode, 2);
    });

    test('没有 versionCode 时退回比版本名', () {
      expect(
        parse(<String, Object?>{
          'version': '1.1.0',
          'url': 'https://example.com/a.apk',
        }).hasUpdate,
        isTrue,
      );
      expect(
        parse(<String, Object?>{
          'version': '0.9.0',
          'url': 'https://example.com/a.apk',
        }).hasUpdate,
        isFalse,
      );
    });

    test('versionCode 优先于版本名', () {
      // 服务端版本名写错了，但 versionCode 明确说没更新
      final UpgradeInfo info = parse(<String, Object?>{
        'version': '9.9.9',
        'versionCode': 1,
        'url': 'https://example.com/a.apk',
      });
      expect(info.hasUpdate, isFalse, reason: 'versionCode 才是准的');
    });

    test('服务端说有更新但版本没变，照样不提示', () {
      // 不信任服务端自报的字段，本地自己比一遍
      final UpgradeInfo info = parse(<String, Object?>{
        'hasUpdate': true,
        'version': '1.0.0',
        'versionCode': 1,
        'url': 'https://example.com/a.apk',
      });
      expect(info.hasUpdate, isFalse);
    });

    test('没有下载地址就不提示更新——提示了也没法装', () {
      final UpgradeInfo info = parse(<String, Object?>{
        'version': '2.0.0',
        'versionCode': 9,
      });
      expect(info.hasUpdate, isFalse);
      expect(info.downloadable, isFalse);
    });

    test('字段名换一种写法也认', () {
      final UpgradeInfo info = parse(<String, Object?>{
        'versionName': '1.2.0',
        'buildNumber': '5',
        'downloadUrl': 'https://example.com/b.apk',
        'changelog': '改了点东西',
      });
      expect(info.hasUpdate, isTrue);
      expect(info.version, '1.2.0');
      expect(info.versionCode, 5);
      expect(info.url, 'https://example.com/b.apk');
      expect(info.note, '改了点东西');
    });

    test('强制更新', () {
      expect(
        parse(<String, Object?>{
          'version': '1.1.0',
          'url': 'https://example.com/a.apk',
          'force': true,
        }).force,
        isTrue,
      );
      expect(
        parse(<String, Object?>{
          'version': '1.1.0',
          'url': 'https://example.com/a.apk',
          'forceUpdate': true,
        }).force,
        isTrue,
      );
    });

    test('空对象不崩，当成没有更新', () {
      final UpgradeInfo info = parse(<String, Object?>{});
      expect(info.hasUpdate, isFalse);
      expect(info.version, '');
      expect(info.note, '');
    });
  });
}
