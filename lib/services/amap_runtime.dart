import 'package:amap_map/amap_map.dart';
import 'package:flutter/widgets.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../config/amap_config.dart';
import '../data/settings_repository.dart';
import '../models/app_settings.dart';

/// 把设置里的底图样式翻译成高德的 MapType。
MapType amapTypeOf(MapKind kind) {
  switch (kind) {
    case MapKind.standard:
      return MapType.normal;
    case MapKind.satellite:
      return MapType.satellite;
    case MapKind.night:
      return MapType.night;
  }
}

/// 高德 SDK 的运行时状态。
///
/// 高德要求 App 在使用地图前，先把「隐私政策已包含高德条款、已弹窗告知、已取得同意」
/// 三个状态告诉 SDK，任何一项为 false 地图都会白屏。
/// 这里把用户的真实同意结果持久化下来，同意前不创建任何地图实例。
class AmapRuntime {
  AmapRuntime._();

  static final AmapRuntime instance = AmapRuntime._();

  final ValueNotifier<bool> privacyAgreed = ValueNotifier<bool>(false);

  bool _initialized = false;

  /// 地图当前是否可用：配了 Key 且用户已同意隐私声明。
  bool get mapReady => AmapConfig.hasKey && privacyAgreed.value;

  /// 启动时读取一次同意状态，已同意则直接告知 SDK。
  Future<void> restore() async {
    final bool agreed = await SettingsRepository.instance
        .getBool(SettingsRepository.keyPrivacyAgreed);
    privacyAgreed.value = agreed;
    if (agreed) _applyPrivacy(true);
  }

  /// 用户在弹窗里做出选择后调用。
  Future<void> setAgreed(bool agreed) async {
    await SettingsRepository.instance
        .setBool(SettingsRepository.keyPrivacyAgreed, agreed);
    privacyAgreed.value = agreed;
    _applyPrivacy(agreed);
  }

  /// 传 Key 给 SDK。需要 context 做图片资源适配，所以在有 context 时调用。
  void initSdk(BuildContext context) {
    if (_initialized || !AmapConfig.hasKey) return;
    _initialized = true;
    AMapInitializer.init(
      context,
      apiKey: const AMapApiKey(
        androidKey: AmapConfig.androidKey,
        iosKey: AmapConfig.iosKey,
      ),
    );
  }

  void _applyPrivacy(bool agreed) {
    AMapInitializer.updatePrivacyAgree(
      AMapPrivacyStatement(
        hasContains: agreed,
        hasShow: agreed,
        hasAgree: agreed,
      ),
    );
  }
}
