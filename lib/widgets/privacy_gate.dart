import 'package:flutter/material.dart';

import '../services/amap_runtime.dart';
import '../theme/app_theme.dart';

/// 弹一次高德隐私声明，返回用户的选择（关掉弹窗按不同意处理）。
///
/// 抽成函数是因为有两个入口：首次启动的 [PrivacyGate]，
/// 以及用户在设置页刚填完 Key、还没同意过的时候。
Future<bool> showAmapPrivacyDialog(BuildContext context) async {
  final bool? agreed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('隐私声明'),
      content: const SingleChildScrollView(
        child: Text(
          '本应用的标记、照片和录音都保存在你的手机本地，不会上传。\n\n'
          '地图显示与地址解析使用高德地图 SDK，SDK 会按其隐私政策处理'
          '位置等必要信息。点击「同意」表示你已阅读并同意包含《高德开放平台'
          '隐私权政策》在内的隐私声明。\n\n'
          '不同意也可以继续使用，此时地图会显示为本地示意图。',
          style: TextStyle(fontSize: 14, height: 1.6),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
          ),
          child: const Text('暂不同意'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(minimumSize: const Size(88, 42)),
          child: const Text('同意'),
        ),
      ],
    ),
  );
  return agreed ?? false;
}

/// 高德合规要求：使用地图前必须先把隐私政策弹窗告知用户并取得同意。
/// 这里在首次启动时弹一次，结果存进本地数据库，同意后地图才会加载。
class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAsk());
  }

  Future<void> _maybeAsk() async {
    final AmapRuntime runtime = AmapRuntime.instance;
    // 没有可用 Key 时地图本来就走本地示意图，不需要打扰用户。
    // 用户之后在设置页填了 Key，会在那里再问一次。
    if (!runtime.hasKey || runtime.privacyAgreed.value) return;

    final bool agreed = await showAmapPrivacyDialog(context);
    await runtime.setAgreed(agreed);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
