import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/location_mark.dart';
import '../services/navigation_launcher.dart';
import '../theme/app_theme.dart';

/// 选择用哪个地图应用导航；一个都没装时给出兜底（复制坐标）。
class NavAppSheet extends StatelessWidget {
  const NavAppSheet({super.key, required this.mark, required this.apps});

  final LocationMark mark;
  final List<NavApp> apps;

  /// 探测可用应用后弹出选择面板。只有一个可用时直接唤起，不多问一步。
  static Future<void> show(BuildContext context, LocationMark mark) async {
    final List<NavApp> apps =
        await NavigationLauncher.instance.availableApps(mark);
    if (!context.mounted) return;

    if (apps.length == 1) {
      final bool ok = await NavigationLauncher.instance.launch(apps.first, mark);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('唤起${apps.first.label}失败')),
        );
      }
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => NavAppSheet(mark: mark, apps: apps),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.divider,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '导航到「${mark.name}」',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (apps.isEmpty)
              _EmptyApps(mark: mark)
            else
              ...apps.map(
                (NavApp app) => ListTile(
                  leading: const Icon(Icons.navigation_outlined,
                      color: AppColors.primary),
                  title: Text(app.label),
                  onTap: () async {
                    Navigator.of(context).pop();
                    await NavigationLauncher.instance.launch(app, mark);
                  },
                ),
              ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                '取消',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyApps extends StatelessWidget {
  const _EmptyApps({required this.mark});

  final LocationMark mark;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Text(
            '没有检测到可用的地图应用',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(text: mark.coordinateText),
            );
            if (!context.mounted) return;
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('坐标已复制，可粘贴到地图应用里')),
            );
          },
          icon: const Icon(Icons.copy_outlined, size: 18),
          label: const Text('复制坐标'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(46),
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.divider),
          ),
        ),
      ],
    );
  }
}
