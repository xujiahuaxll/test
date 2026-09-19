import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/config/amap_config.dart';

/// Key 的取舍规则：同一个 APK 发给不同的人，各自填自己的 Key。
void main() {
  group('resolveKey', () {
    const String userKey = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
    const String buildKey = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

    test('用户填了就用用户的，盖过打包时内置的', () {
      expect(AmapConfig.resolveKey(userKey, buildKey), userKey);
    });

    test('用户没填就回落到打包时内置的', () {
      expect(AmapConfig.resolveKey('', buildKey), buildKey);
      // 只敲了空格等于没填
      expect(AmapConfig.resolveKey('   ', buildKey), buildKey);
    });

    test('两个都没有时为空，界面据此退回示意图', () {
      expect(AmapConfig.resolveKey('', ''), isEmpty);
    });

    test('粘贴时常见的首尾空白会被去掉', () {
      expect(AmapConfig.resolveKey('  $userKey\n', ''), userKey);
      expect(AmapConfig.resolveKey('', ' $buildKey '), buildKey);
    });
  });

  group('looksLikeKey', () {
    test('32 位十六进制串算合法', () {
      expect(AmapConfig.looksLikeKey('0123456789abcdef0123456789ABCDEF'),
          isTrue);
      // 前后有空白也接受，保存时会 trim
      expect(
        AmapConfig.looksLikeKey('  0123456789abcdef0123456789abcdef  '),
        isTrue,
      );
    });

    test('长度不对或含非法字符的一律拦下', () {
      expect(AmapConfig.looksLikeKey(''), isFalse);
      // 31 位
      expect(AmapConfig.looksLikeKey('0123456789abcdef0123456789abcde'),
          isFalse);
      // 33 位
      expect(AmapConfig.looksLikeKey('0123456789abcdef0123456789abcdef0'),
          isFalse);
      // 含非十六进制字母
      expect(AmapConfig.looksLikeKey('0123456789abcdef0123456789abcdez'),
          isFalse);
      // 中间有空格
      expect(AmapConfig.looksLikeKey('0123456789abcdef 123456789abcdef'),
          isFalse);
    });
  });

  group('mask', () {
    test('只露出首尾，中间打点', () {
      expect(
        AmapConfig.mask('0123456789abcdef0123456789abcdef'),
        '0123******cdef',
      );
    });

    test('太短的串原样返回，不至于把内容遮没', () {
      expect(AmapConfig.mask('abcd'), 'abcd');
      expect(AmapConfig.mask(''), isEmpty);
    });
  });
}
