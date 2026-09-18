import 'dart:io';

/// 高德 Key 从编译期变量读取，不写进仓库：
///
/// flutter run --dart-define=AMAP_ANDROID_KEY=xxx --dart-define=AMAP_IOS_KEY=yyy
///
/// 没配 Key 时地图组件会自动退回本地示意图，App 其余功能不受影响。
class AmapConfig {
  AmapConfig._();

  static const String androidKey =
      String.fromEnvironment('AMAP_ANDROID_KEY');
  static const String iosKey = String.fromEnvironment('AMAP_IOS_KEY');

  static String get currentKey {
    if (Platform.isAndroid) return androidKey;
    if (Platform.isIOS) return iosKey;
    return '';
  }

  static bool get hasKey => currentKey.isNotEmpty;
}
