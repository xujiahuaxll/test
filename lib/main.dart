import 'package:flutter/material.dart';

import 'data/marker_repository.dart';
import 'pages/marker_list_page.dart';
import 'services/amap_runtime.dart';
import 'services/media_store.dart';
import 'services/settings_controller.dart';
import 'theme/app_theme.dart';
import 'widgets/privacy_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热应用目录，之后界面可以同步拿到照片 / 录音的绝对路径。
  await MediaStore.instance.warmUp();
  // 首次启动时建库（含预置标签）。
  await MarkerRepository.instance.count();
  // 读取此前的高德隐私声明同意状态，已同意的话直接告知 SDK。
  await AmapRuntime.instance.restore();
  // 读取用户在设置页存下的配置，之后各处同步取用。
  await SettingsController.instance.load();
  runApp(const LocationMarkerApp());
}

/// 踩点：数据存在本机 SQLite 与应用私有目录，只有主动点同步时才联网。
class LocationMarkerApp extends StatelessWidget {
  const LocationMarkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '踩点',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const PrivacyGate(child: MarkerListPage()),
    );
  }
}
