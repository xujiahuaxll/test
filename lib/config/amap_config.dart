import 'dart:io';

/// 高德 Key 的来源与取舍。
///
/// 有两个来源，运行时优先：
/// 1. **用户在设置页填的 Key**，存在内置数据库里，每台设备可以不一样；
/// 2. **打包时注入的 Key**（`--dart-define=AMAP_ANDROID_KEY=xxx`），作为默认值。
///
/// 两个都没有时地图组件退回本地示意图，App 其余功能不受影响。
class AmapConfig {
  AmapConfig._();

  /// 打包时注入的默认 Key，不写进仓库。
  static const String buildAndroidKey = String.fromEnvironment(
    'AMAP_ANDROID_KEY',
  );
  static const String buildIosKey = String.fromEnvironment('AMAP_IOS_KEY');

  /// 当前平台打包时注入的 Key。
  static String get buildKey {
    if (Platform.isAndroid) return buildAndroidKey;
    if (Platform.isIOS) return buildIosKey;
    return '';
  }

  /// 用户填的优先，没填就用打包时注入的。抽成纯函数方便测试。
  static String resolveKey(String userKey, String fallback) {
    final String trimmed = userKey.trim();
    return trimmed.isEmpty ? fallback.trim() : trimmed;
  }

  /// 高德 Key 是 32 位的十六进制串。只做长度与字符的粗校验，
  /// 真正有没有效要等 SDK 联网鉴权，填错了地图会白屏。
  static bool looksLikeKey(String key) {
    final String trimmed = key.trim();
    return RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(trimmed);
  }

  /// 打点显示，避免把整串 Key 亮在界面上。
  static String mask(String key) {
    final String trimmed = key.trim();
    if (trimmed.length <= 8) return trimmed;
    return '${trimmed.substring(0, 4)}'
        '${'*' * 6}'
        '${trimmed.substring(trimmed.length - 4)}';
  }
}
