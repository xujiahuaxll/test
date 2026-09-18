import 'package:flutter/material.dart';

import 'data/marker_repository.dart';
import 'services/media_store.dart';
import 'pages/marker_list_page.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 预热应用目录，之后界面可以同步拿到照片 / 录音的绝对路径。
  await MediaStore.instance.warmUp();
  // 首次启动时建库（含预置标签）。
  await MarkerRepository.instance.count();
  runApp(const LocationMarkerApp());
}

/// 地点标记 App：数据全部存在本机 SQLite 与应用私有目录，不连任何服务端。
class LocationMarkerApp extends StatelessWidget {
  const LocationMarkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '地点标记',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const MarkerListPage(),
    );
  }
}
