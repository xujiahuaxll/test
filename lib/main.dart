import 'package:flutter/material.dart';

import 'pages/marker_list_page.dart';
import 'theme/app_theme.dart';

void main() => runApp(const LocationMarkerApp());

/// 地点标记 App —— 界面演示版本。
/// 所有数据均为静态假数据，定位 / 相机 / 录音都只做视觉模拟。
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
