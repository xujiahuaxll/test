import 'dart:io';

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

/// 高德 SDK 的运行时状态：Key 与隐私合规。
///
/// Key 可以由用户在设置页自己填（存本机数据库），没填则用打包时注入的默认值——
/// 这样同一个 APK 发给不同的人，各自用自己的 Key。
///
/// 隐私方面高德要求先把「隐私政策已包含高德条款、已弹窗告知、已取得同意」
/// 三个状态告诉 SDK，任何一项为 false 地图都会白屏。
/// 这里把用户的真实同意结果持久化下来，同意前不创建任何地图实例。
class AmapRuntime {
  AmapRuntime._();

  static final AmapRuntime instance = AmapRuntime._();

  /// 用户是否已同意包含高德条款的隐私声明。
  final ValueNotifier<bool> privacyAgreed = ValueNotifier<bool>(false);

  /// 用户在设置页填的 Key（当前平台）。空串表示没填，走打包时注入的默认值。
  final ValueNotifier<String> userKey = ValueNotifier<String>('');

  /// Key 或同意状态任一变化都会通知，地图组件据此重建。
  late final Listenable changes =
      Listenable.merge(<Listenable>[privacyAgreed, userKey]);

  /// 上一次交给 SDK 的 Key，用来判断要不要重新 init。
  String? _initializedKey;

  /// 实际生效的 Key：用户填的优先。
  String get effectiveKey =>
      AmapConfig.resolveKey(userKey.value, AmapConfig.buildKey);

  bool get hasKey => effectiveKey.isNotEmpty;

  /// Key 是不是打包时带进来的默认值（用户没自己填）。
  bool get usingBuildKey =>
      userKey.value.trim().isEmpty && AmapConfig.buildKey.isNotEmpty;

  /// 地图当前是否可用：有 Key 且用户已同意隐私声明。
  bool get mapReady => hasKey && privacyAgreed.value;

  /// 当前平台对应的存储键。两个平台分开存，换平台不会读到对方的 Key。
  static String get _platformKeyName => Platform.isIOS
      ? SettingsRepository.keyAmapIosKey
      : SettingsRepository.keyAmapAndroidKey;

  /// 启动时读一次同意状态与用户 Key，已同意则直接告知 SDK。
  Future<void> restore() async {
    final SettingsRepository repo = SettingsRepository.instance;
    userKey.value = (await repo.getString(_platformKeyName) ?? '').trim();
    final bool agreed =
        await repo.getBool(SettingsRepository.keyPrivacyAgreed);
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

  /// 保存用户自己的 Key；传空串表示清除，回落到打包时注入的默认值。
  ///
  /// 插件在每次创建地图 PlatformView 时都会把 Key 传给原生侧，
  /// 原生侧发现和上次不同就调 MapsInitializer.setApiKey，
  /// 所以这里只要让下次 init 重新跑一遍，新 Key 下次打开地图就生效。
  Future<void> setUserKey(String key) async {
    final String trimmed = key.trim();
    await SettingsRepository.instance.setString(_platformKeyName, trimmed);
    userKey.value = trimmed;
    _initializedKey = null;
  }

  /// 传 Key 给 SDK。需要 context 做图片资源适配，所以在有 context 时调用。
  void initSdk(BuildContext context) {
    final String key = effectiveKey;
    if (key.isEmpty || _initializedKey == key) return;
    _initializedKey = key;
    AMapInitializer.init(
      context,
      apiKey: AMapApiKey(
        androidKey: Platform.isIOS ? AmapConfig.buildAndroidKey : key,
        iosKey: Platform.isIOS ? key : AmapConfig.buildIosKey,
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
