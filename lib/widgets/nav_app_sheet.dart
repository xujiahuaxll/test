import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/location_mark.dart';
import '../services/navigation_launcher.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';

/// 选择用哪个地图应用导航；一个都没装时给出兜底（复制坐标）。
class NavAppSheet extends StatelessWidget {
  const NavAppSheet({super.key, required this.mark, required this.apps});

  final LocationMark mark;
  final List<NavApp> apps;

  /// 探测可用应用后弹出选择面板。
  ///
  /// 设置里指定了默认导航应用、且它确实装了的话直接唤起；
  /// 只有一个可用时同样不多问一步。
  static Future<void> show(BuildContext context, LocationMark mark) async {
    final List<NavApp> apps =
        await NavigationLauncher.instance.availableApps(mark);
    if (!context.mounted) return;

    final NavApp? preferred = SettingsController.instance.value.defaultNavApp;
    final NavApp? direct = preferred != null && apps.contains(preferred)
        ? preferred
        : (apps.length == 1 ? apps.first : null);

    if (direct != null) {
      final bool ok = await NavigationLauncher.instance.launch(direct, mark);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('唤起${direct.label}失败')),
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
    // 背景色画在 Material 上：里面的 ListTile 要在最近的 Material 上画水波纹，
    // 用 Container 的 decoration 会把它整块盖住。
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
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
