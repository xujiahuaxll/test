import 'package:flutter/foundation.dart';

import '../data/settings_repository.dart';
import '../models/app_settings.dart';

/// 全局配置的持有者。
///
/// 启动时从内置数据库读一次，之后各处同步读 [value]；
/// 设置页改动后落库并通知界面刷新。没调用 [load] 时返回的是默认配置，
/// 所以单元测试里直接读也不会出问题。
class SettingsController extends ChangeNotifier {
  SettingsController({SettingsRepository? repository})
      : _repo = repository ?? SettingsRepository.instance;

  static final SettingsController instance = SettingsController();

  final SettingsRepository _repo;

  AppSettings _value = const AppSettings();

  AppSettings get value => _value;

  Future<void> load() async {
    _value = await _repo.loadSettings();
    notifyListeners();
  }

  /// 整体替换。只有真的变了才写库、才通知。
  Future<void> update(AppSettings next) async {
    final AppSettings previous = _value;
    if (mapEquals(previous.toMap(), next.toMap())) return;
    _value = next;
    notifyListeners();
    await _repo.saveSettings(next, previous: previous);
  }

  /// 把所有配置项恢复成默认值。
  Future<void> resetToDefaults() => update(const AppSettings());
}
