import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../config/amap_config.dart';
import '../data/marker_repository.dart';
import '../data/settings_repository.dart';
import '../models/app_settings.dart';
import '../services/amap_location_service.dart';
import '../services/amap_runtime.dart';
import '../services/media_store.dart';
import '../services/navigation_launcher.dart';
import '../services/settings_controller.dart';
import '../services/upgrade_service.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/privacy_gate.dart';

/// 系统设置：导航、地图、定位、录音转写、照片、列表排序都在这里配。
///
/// 改动即时落到内置数据库，各处功能下次执行时读到的就是新值。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsController _controller = SettingsController.instance;

  MediaUsage? _usage;
  bool _cleaning = false;
  AppSignature? _signature;

  /// 检查更新的服务地址与本机版本。地址为空表示还没配。
  String _upgradeApi = '';
  AppVersion? _version;
  bool _checkingUpgrade = false;

  /// 云端同步的三项配置。三项齐全才算配好，缺一不可。
  String _cloudApi = '';
  String _cloudAccount = '';
  String _cloudPassword = '';

  bool get _cloudReady =>
      _cloudApi.isNotEmpty &&
      _cloudAccount.isNotEmpty &&
      _cloudPassword.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onSettingsChanged);
    _loadUsage();
    _loadSignature();
    _loadUpgradeConfig();
    _loadCloudConfig();
  }

  @override
  void dispose() {
    _controller.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSignature() async {
    final AppSignature? signature =
        await AmapLocationService.instance.appSignature();
    if (!mounted) return;
    setState(() => _signature = signature);
  }

  Future<void> _loadUpgradeConfig() async {
    final String api =
        (await SettingsRepository.instance.getString(
              SettingsRepository.keyUpgradeApi,
            ) ??
            '')
            .trim();
    // 读版本号走的是平台通道，在没有原生实现的环境里会抛。
    // 它只是显示用的，不该把整个设置页拖垮。
    AppVersion? version;
    try {
      version = await UpgradeService.instance.currentVersion();
    } catch (_) {
      version = null;
    }
    if (!mounted) return;
    setState(() {
      _upgradeApi = api;
      _version = version;
    });
  }

  Future<void> _loadCloudConfig() async {
    final SettingsRepository repo = SettingsRepository.instance;
    final String api =
        (await repo.getString(SettingsRepository.keyCloudApi) ?? '').trim();
    final String account =
        (await repo.getString(SettingsRepository.keyCloudAccount) ?? '').trim();
    final String password =
        (await repo.getString(SettingsRepository.keyCloudPassword) ?? '').trim();
    if (!mounted) return;
    setState(() {
      _cloudApi = api;
      _cloudAccount = account;
      _cloudPassword = password;
    });
  }

  /// 云端三项共用一个编辑流程，省得写三遍一模一样的代码。
  Future<void> _editCloudField({
    required String key,
    required String title,
    required String description,
    required String current,
    required ValueChanged<String> onSaved,
    String hint = '',
    bool obscure = false,
    TextInputType keyboard = TextInputType.text,
  }) async {
    final String? next = await showDialog<String>(
      context: context,
      builder: (_) => _TextConfigDialog(
        title: title,
        description: description,
        initial: current,
        hint: hint,
        obscure: obscure,
        keyboard: keyboard,
      ),
    );
    if (next == null || !mounted) return;
    await SettingsRepository.instance.setString(key, next);
    if (!mounted) return;
    setState(() => onSaved(next));
    _toast(next.isEmpty ? '已清空' : '已保存');
  }

  Future<void> _loadUsage() async {
    final MediaUsage usage = await MediaStore.instance.usage();
    if (!mounted) return;
    setState(() => _usage = usage);
  }

  AppSettings get _settings => _controller.value;

  Future<void> _apply(AppSettings next) => _controller.update(next);

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = _settings;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: <Widget>[
          _Group(
            icon: Icons.navigation_outlined,
            title: '导航',
            children: <Widget>[
              _OptionRow(
                title: '默认导航应用',
                subtitle: '选定后点导航直接打开这个应用，不再弹选择框',
                value: settings.defaultNavApp?.label ?? '每次询问',
                onTap: _pickDefaultNavApp,
              ),
              _OptionRow(
                title: '出行方式',
                subtitle: '唤起地图时使用的路线类型',
                value: settings.travelMode.label,
                onTap: _pickTravelMode,
              ),
            ],
          ),
          _Group(
            icon: Icons.map_outlined,
            title: '地图',
            children: <Widget>[
              _OptionRow(
                title: '底图样式',
                value: settings.mapKind.label,
                onTap: _pickMapKind,
              ),
              _SwitchRow(
                title: '实时路况',
                subtitle: '在全部标记的地图上叠加拥堵图层',
                value: settings.showTraffic,
                onChanged: (bool on) =>
                    _apply(settings.copyWith(showTraffic: on)),
              ),
              _AmapKeyRow(onTap: _editAmapKey),
              _PrivacyRow(onChanged: _onPrivacyChanged),
              _CopyRow(
                title: '应用包名',
                value: _signature?.packageName,
                hint: '到高德后台登记 Key 时填这个',
                onCopy: _copy,
              ),
              _CopyRow(
                title: '签名 SHA1',
                value: _signature?.sha1,
                hint: '换一版安装包这个值就会变，'
                    '变了要回高德后台改绑，否则报错误码 1009',
                onCopy: _copy,
              ),
            ],
          ),
          _Group(
            icon: Icons.my_location_outlined,
            title: '定位',
            children: <Widget>[
              _OptionRow(
                title: '定位精度',
                subtitle: settings.locateAccuracy.hint,
                value: settings.locateAccuracy.label,
                onTap: _pickAccuracy,
              ),
              _OptionRow(
                title: '定位超时',
                subtitle: '超过这个时间还没定到就提示重试',
                value: '${settings.locateTimeoutSeconds} 秒',
                onTap: _pickTimeout,
              ),
              _SwitchRow(
                title: '自动解析地址',
                subtitle: '定位后把经纬度转成文字地址；关掉只记录坐标',
                value: settings.reverseGeocode,
                onChanged: (bool on) =>
                    _apply(settings.copyWith(reverseGeocode: on)),
              ),
            ],
          ),
          _Group(
            icon: Icons.mic_none_outlined,
            title: '备注与录音',
            children: <Widget>[
              _OptionRow(
                title: '语音识别语言',
                subtitle: '录音转文字使用的识别语言',
                value: settings.speechLocale.label,
                onTap: _pickSpeechLocale,
              ),
              _OptionRow(
                title: '录音音质',
                subtitle: settings.audioQuality.hint,
                value: settings.audioQuality.label,
                onTap: _pickAudioQuality,
              ),
            ],
          ),
          _Group(
            icon: Icons.photo_outlined,
            title: '照片',
            children: <Widget>[
              _OptionRow(
                title: '保存质量',
                subtitle: settings.photoQuality.hint,
                value: settings.photoQuality.label,
                onTap: _pickPhotoQuality,
              ),
            ],
          ),
          _Group(
            icon: Icons.list_alt_outlined,
            title: '列表',
            children: <Widget>[
              _OptionRow(
                title: '默认排序',
                value: settings.markerSort.label,
                onTap: _pickSort,
              ),
            ],
          ),
          _Group(
            icon: Icons.folder_outlined,
            title: '存储',
            children: <Widget>[
              _InfoRow(
                title: '照片与录音占用',
                value: _usage == null ? '统计中…' : _usage!.readableSize,
                hint: _usage == null
                    ? null
                    : '${_usage!.photoCount} 张照片 · '
                        '${_usage!.audioCount} 段录音',
              ),
              _ActionRow(
                title: '清理未引用文件',
                subtitle: '删掉已经没有标记引用的照片和录音',
                busy: _cleaning,
                onTap: _cleanOrphans,
              ),
            ],
          ),
          _Group(
            icon: Icons.cloud_outlined,
            title: '云端存储',
            children: <Widget>[
              _OptionRow(
                title: '同步服务地址',
                subtitle: _cloudApi.isEmpty
                    ? '没配地址，同步不可用。点这里填自己的接口'
                    : _cloudApi,
                value: _cloudApi.isEmpty ? '未填写' : '已填写',
                onTap: () => _editCloudField(
                  key: SettingsRepository.keyCloudApi,
                  title: '同步服务地址',
                  description: '标记数据会发到这个地址上。接口格式见仓库里的 '
                      'docs/api.md。\n\n'
                      '务必用 https —— 账号密码和你的全部标记都要经过它。',
                  current: _cloudApi,
                  hint: 'https://example.com/sync',
                  keyboard: TextInputType.url,
                  onSaved: (String v) => _cloudApi = v,
                ),
              ),
              _OptionRow(
                title: '手机号',
                subtitle: _cloudAccount.isEmpty ? '同步时用它标识是谁的数据' : _cloudAccount,
                value: _cloudAccount.isEmpty ? '未填写' : '已填写',
                onTap: () => _editCloudField(
                  key: SettingsRepository.keyCloudAccount,
                  title: '手机号',
                  description: '同步时随请求一起发给你的服务端，用来区分这是谁的数据。',
                  current: _cloudAccount,
                  hint: '13800000000',
                  keyboard: TextInputType.phone,
                  onSaved: (String v) => _cloudAccount = v,
                ),
              ),
              _OptionRow(
                title: '密码',
                subtitle: _cloudPassword.isEmpty
                    ? '和手机号一起发给服务端校验'
                    : '已设置（不显示）',
                value: _cloudPassword.isEmpty ? '未填写' : '已填写',
                onTap: () => _editCloudField(
                  key: SettingsRepository.keyCloudPassword,
                  title: '密码',
                  description: '这个密码以明文存在本机数据库里。\n\n'
                      '所以别用你其它账号的密码，也别用会心疼的那个。',
                  current: _cloudPassword,
                  obscure: true,
                  onSaved: (String v) => _cloudPassword = v,
                ),
              ),
              _InfoRow(
                title: '状态',
                value: _cloudReady ? '可以同步' : '未启用',
                hint: _cloudReady
                    ? '回列表页，右上角的同步按钮就能用了'
                    : '三项都填齐才会启用同步',
              ),
            ],
          ),
          _Group(
            icon: Icons.system_update_outlined,
            title: '更新',
            children: <Widget>[
              _InfoRow(
                title: '当前版本',
                value: _version?.toString() ?? '读不到',
              ),
              _OptionRow(
                title: '检查更新地址',
                subtitle: _upgradeApi.isEmpty
                    ? '没配地址，检查更新不可用。点这里填自己的接口'
                    : _upgradeApi,
                value: _upgradeApi.isEmpty ? '未填写' : '已填写',
                onTap: _editUpgradeApi,
              ),
              if (_upgradeApi.isNotEmpty)
                _ActionRow(
                  title: '检查更新',
                  subtitle: '有新版本就下载并唤起安装',
                  busy: _checkingUpgrade,
                  onTap: _checkUpgrade,
                ),
            ],
          ),
          _Group(
            icon: Icons.tune_outlined,
            title: '其他',
            children: <Widget>[
              _ActionRow(
                title: '系统权限设置',
                subtitle: '定位、麦克风、相机、相册的授权在系统里管理',
                onTap: () => openAppSettings(),
              ),
              _ActionRow(
                title: '恢复默认设置',
                subtitle: '只重置本页的配置项，标记数据不受影响',
                danger: true,
                onTap: _confirmReset,
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 18),
            child: Text(
              '标记、照片、录音和这里的配置都存在本机。\n'
              '只有你自己配了云端地址、并主动点同步时，数据才会发出去。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: AppColors.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---- 各项的选择逻辑 ----

  Future<void> _pickDefaultNavApp() async {
    final List<_Choice<NavApp?>> choices = <_Choice<NavApp?>>[
      const _Choice<NavApp?>(null, '每次询问', hint: '每次都弹出可用的地图应用列表'),
      for (final NavApp app in NavigationLauncher.candidates())
        _Choice<NavApp?>(app, app.label),
    ];
    final _Choice<NavApp?>? picked = await _pick<NavApp?>(
      '默认导航应用',
      choices,
      _settings.defaultNavApp,
    );
    if (picked == null) return;
    await _apply(
      picked.value == null
          ? _settings.copyWith(clearDefaultNavApp: true)
          : _settings.copyWith(defaultNavApp: picked.value),
    );
  }

  Future<void> _pickTravelMode() async {
    final _Choice<TravelMode>? picked = await _pick<TravelMode>(
      '出行方式',
      <_Choice<TravelMode>>[
        for (final TravelMode mode in TravelMode.values)
          _Choice<TravelMode>(mode, mode.label),
      ],
      _settings.travelMode,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(travelMode: picked.value));
    }
  }

  Future<void> _pickMapKind() async {
    final _Choice<MapKind>? picked = await _pick<MapKind>(
      '底图样式',
      <_Choice<MapKind>>[
        for (final MapKind kind in MapKind.values)
          _Choice<MapKind>(kind, kind.label),
      ],
      _settings.mapKind,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(mapKind: picked.value));
    }
  }

  Future<void> _pickAccuracy() async {
    final _Choice<LocateAccuracy>? picked = await _pick<LocateAccuracy>(
      '定位精度',
      <_Choice<LocateAccuracy>>[
        for (final LocateAccuracy item in LocateAccuracy.values)
          _Choice<LocateAccuracy>(item, item.label, hint: item.hint),
      ],
      _settings.locateAccuracy,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(locateAccuracy: picked.value));
    }
  }

  Future<void> _pickTimeout() async {
    final _Choice<int>? picked = await _pick<int>(
      '定位超时',
      <_Choice<int>>[
        for (final int seconds in kLocateTimeoutChoices)
          _Choice<int>(seconds, '$seconds 秒'),
      ],
      _settings.locateTimeoutSeconds,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(locateTimeoutSeconds: picked.value));
    }
  }

  Future<void> _pickSpeechLocale() async {
    final _Choice<SpeechLocale>? picked = await _pick<SpeechLocale>(
      '语音识别语言',
      <_Choice<SpeechLocale>>[
        for (final SpeechLocale item in SpeechLocale.values)
          _Choice<SpeechLocale>(item, item.label, hint: item.id),
      ],
      _settings.speechLocale,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(speechLocale: picked.value));
    }
  }

  Future<void> _pickAudioQuality() async {
    final _Choice<AudioQuality>? picked = await _pick<AudioQuality>(
      '录音音质',
      <_Choice<AudioQuality>>[
        for (final AudioQuality item in AudioQuality.values)
          _Choice<AudioQuality>(item, item.label, hint: item.hint),
      ],
      _settings.audioQuality,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(audioQuality: picked.value));
    }
  }

  Future<void> _pickPhotoQuality() async {
    final _Choice<PhotoQuality>? picked = await _pick<PhotoQuality>(
      '照片保存质量',
      <_Choice<PhotoQuality>>[
        for (final PhotoQuality item in PhotoQuality.values)
          _Choice<PhotoQuality>(item, item.label, hint: item.hint),
      ],
      _settings.photoQuality,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(photoQuality: picked.value));
    }
  }

  Future<void> _pickSort() async {
    final _Choice<MarkerSort>? picked = await _pick<MarkerSort>(
      '默认排序',
      <_Choice<MarkerSort>>[
        for (final MarkerSort item in MarkerSort.values)
          _Choice<MarkerSort>(item, item.label),
      ],
      _settings.markerSort,
    );
    if (picked != null) {
      await _apply(_settings.copyWith(markerSort: picked.value));
    }
  }

  /// 打开 Key 输入弹窗，保存后让地图用新 Key 重建。
  Future<void> _editAmapKey() async {
    final AmapRuntime runtime = AmapRuntime.instance;
    final _KeyEditResult? result = await showDialog<_KeyEditResult>(
      context: context,
      builder: (BuildContext dialogContext) =>
          _AmapKeyDialog(initial: runtime.userKey.value),
    );
    if (result == null || !mounted) return;

    await runtime.setUserKey(result.key);
    if (!mounted) return;

    if (result.key.isEmpty) {
      _toast(AmapConfig.buildKey.isEmpty
          ? '已清除，地图将显示为本地示意图'
          : '已清除，回到打包时内置的 Key');
      return;
    }

    // 刚填上 Key 但还没同意过隐私声明的话，这里补问一次，
    // 否则地图仍然会白屏，用户会以为 Key 填错了。
    if (!runtime.privacyAgreed.value) {
      final bool agreed = await showAmapPrivacyDialog(context);
      await runtime.setAgreed(agreed);
      if (!mounted) return;
      if (!agreed) {
        _toast('Key 已保存；同意隐私声明后地图才会加载');
        return;
      }
    }
    _toast('Key 已保存，重新打开地图即可生效');
  }

  Future<void> _editUpgradeApi() async {
    final String? next = await showDialog<String>(
      context: context,
      builder: (_) => _TextConfigDialog(
        title: '检查更新地址',
        initial: _upgradeApi,
        hint: 'https://example.com/latest',
        description: '填一个自己的接口地址。App 会带上当前版本号去问它有没有'
            '新版本，拿到 APK 地址后下载安装。\n\n'
            '接口格式见仓库里的 docs/api.md。清空保存就是关掉这个功能。',
        keyboard: TextInputType.url,
      ),
    );
    if (next == null || !mounted) return;
    await SettingsRepository.instance
        .setString(SettingsRepository.keyUpgradeApi, next);
    if (!mounted) return;
    setState(() => _upgradeApi = next);
    _toast(next.isEmpty ? '已关闭检查更新' : '已保存');
  }

  /// 检查更新。全程只在这里弹窗，服务层不碰 UI。
  Future<void> _checkUpgrade() async {
    final AppVersion? current = _version;
    if (_upgradeApi.isEmpty || current == null) return;

    setState(() => _checkingUpgrade = true);
    try {
      final UpgradeInfo info = await UpgradeService.instance.check(
        baseUrl: _upgradeApi,
        current: current,
      );
      if (!mounted) return;
      if (!info.hasUpdate) {
        _toast('已经是最新版本（$current）');
        return;
      }
      final bool go = await _confirmUpgrade(info) ?? false;
      if (!go || !mounted) return;
      await _downloadAndInstall(info);
    } on UpgradeFailure catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      if (mounted) setState(() => _checkingUpgrade = false);
    }
  }

  Future<bool?> _confirmUpgrade(UpgradeInfo info) {
    return showDialog<bool>(
      context: context,
      // 强制更新时不让点外面关掉
      barrierDismissible: !info.force,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('发现新版本 ${info.version}'),
        content: SingleChildScrollView(
          child: Text(
            info.note.isEmpty ? '服务端没有提供更新说明。' : info.note,
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
        actions: <Widget>[
          if (!info.force)
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('以后再说'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('立即更新'),
          ),
        ],
      ),
    );
  }

  /// 下载并唤起安装。进度弹窗自己持有进度，避免刷新整页。
  Future<void> _downloadAndInstall(UpgradeInfo info) async {
    final ValueNotifier<double?> progress = ValueNotifier<double?>(0);
    bool dialogUp = true;
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(progress: progress),
    ).then((_) => dialogUp = false));

    try {
      final File apk = await UpgradeService.instance.download(
        info.url,
        onProgress: (double? p) => progress.value = p,
      );
      if (dialogUp && mounted) Navigator.of(context).pop();
      dialogUp = false;

      final InstallOutcome outcome =
          await UpgradeService.instance.install(apk);
      if (!mounted) return;
      switch (outcome) {
        case InstallOutcome.started:
          break;
        case InstallOutcome.needPermission:
          _toast('请先在系统设置里允许「安装未知应用」，然后回来重试');
        case InstallOutcome.failed:
          _toast('没能唤起安装程序');
      }
    } on UpgradeFailure catch (e) {
      if (dialogUp && mounted) Navigator.of(context).pop();
      if (mounted) _toast(e.message);
    } finally {
      progress.dispose();
    }
  }

  Future<void> _copy(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _toast('$label已复制');
  }

  Future<void> _onPrivacyChanged(bool agreed) async {
    await AmapRuntime.instance.setAgreed(agreed);
    if (!mounted) return;
    _toast(agreed ? '已同意，地图将正常加载' : '已撤回同意，地图会退回本地示意图');
  }

  Future<void> _cleanOrphans() async {
    setState(() => _cleaning = true);
    try {
      final Set<String> referenced =
          await MarkerRepository.instance.referencedMediaPaths();
      final MediaUsage removed =
          await MediaStore.instance.removeOrphans(referenced);
      await _loadUsage();
      if (!mounted) return;
      _toast(
        removed.fileCount == 0
            ? '没有需要清理的文件'
            : '清理了 ${removed.fileCount} 个文件，释放 ${removed.readableSize}',
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  Future<void> _confirmReset() async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('本页的所有配置项会回到初始值，标记数据不会被删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _controller.resetToDefaults();
    if (!mounted) return;
    _toast('已恢复默认设置');
  }

  /// 通用的单选面板。返回 null 表示用户直接关掉了面板。
  Future<_Choice<T>?> _pick<T>(
    String title,
    List<_Choice<T>> choices,
    T current,
  ) {
    return showModalBottomSheet<_Choice<T>>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => _ChoiceSheet<T>(
        title: title,
        choices: choices,
        current: current,
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

/// Key 弹窗的返回值。key 为空串表示「清除，回到内置 Key」。
class _KeyEditResult {
  const _KeyEditResult(this.key);

  final String key;
}

/// 填自己的高德 Key。
///
/// 同一个 APK 会发给不同的人，各自到高德开放平台申请自己的 Key
/// （要绑定这个 App 的包名和签名 SHA1），填在这里，存在本机数据库。
class _AmapKeyDialog extends StatefulWidget {
  const _AmapKeyDialog({required this.initial});

  final String initial;

  @override
  State<_AmapKeyDialog> createState() => _AmapKeyDialogState();
}

class _AmapKeyDialogState extends State<_AmapKeyDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 只提示，不拦截。
  ///
  /// 「32 位十六进制」只是我按现在见到的 Key 归纳出来的，不是高德的承诺。
  /// 拿它当硬性校验，等于哪天格式一变就把用户锁在外面、什么都配不了。
  /// 真正能判定 Key 行不行的是高德服务器，填错了它会回明确的错误码。
  bool get _looksUnusual {
    final String value = _controller.text.trim();
    return value.isNotEmpty && !AmapConfig.looksLikeKey(value);
  }

  void _submit() {
    // 清空表示不再用自己的 Key，同样放行。
    Navigator.of(context).pop(_KeyEditResult(_controller.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('高德地图 Key'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '到高德开放平台申请一个 Android 平台的 Key，'
            '申请时填这个 App 的包名 com.example.location_marker '
            '和你安装包的签名 SHA1。\n\n'
            'Key 只保存在这台手机上，不会上传。',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 1,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: '粘贴高德后台的 Key',
              isDense: true,
            ),
            style: const TextStyle(fontSize: 14, letterSpacing: 0.4),
          ),
          if (_looksUnusual) ...<Widget>[
            const SizedBox(height: 8),
            const Text(
              '看着不像常见的 32 位 Key，可能是漏字或多了空格。'
              '不确定也可以直接保存，能不能用由高德判定。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.45,
                color: AppColors.accent,
              ),
            ),
          ],
          if (widget.initial.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            const Text(
              '清空后保存，就回到打包时内置的 Key（没有内置则地图显示为示意图）。',
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 一个选项的值 + 展示文案。
class _Choice<T> {
  const _Choice(this.value, this.label, {this.hint});

  final T value;
  final String label;
  final String? hint;
}

class _ChoiceSheet<T> extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.choices,
    required this.current,
  });

  final String title;
  final List<_Choice<T>> choices;
  final T current;

  @override
  Widget build(BuildContext context) {
    // 背景色画在 Material 上：ListTile 的水波纹要落在最近的 Material 上，
    // 用 Container 的 decoration 会把它整块盖住。
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
              const SizedBox(height: 14),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: <Widget>[
                    for (final _Choice<T> choice in choices)
                      ListTile(
                        title: Text(choice.label),
                        subtitle: choice.hint == null
                            ? null
                            : Text(
                                choice.hint!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                        trailing: choice.value == current
                            ? const Icon(Icons.check,
                                size: 20, color: AppColors.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(choice),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 通用的文本配置弹窗：说明 + 单行输入 + 取消/保存。
///
/// 升级地址、云端地址、账号、密码都用它，省得每种配置各写一个弹窗。
/// 返回 null 表示取消；返回空串表示用户清空了这项配置。
class _TextConfigDialog extends StatefulWidget {
  const _TextConfigDialog({
    required this.title,
    required this.description,
    this.initial = '',
    this.hint = '',
    this.obscure = false,
    this.keyboard = TextInputType.text,
  });

  final String title;
  final String description;
  final String initial;
  final String hint;
  final bool obscure;
  final TextInputType keyboard;

  @override
  State<_TextConfigDialog> createState() => _TextConfigDialogState();
}

class _TextConfigDialogState extends State<_TextConfigDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.description,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.6,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            autofocus: true,
            maxLines: 1,
            obscureText: widget.obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: widget.keyboard,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(hintText: widget.hint, isDense: true),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }
}

/// 下载进度弹窗。进度值放在 ValueNotifier 里，只重建这一小块。
class _DownloadDialog extends StatelessWidget {
  const _DownloadDialog({required this.progress});

  final ValueListenable<double?> progress;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('正在下载'),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (BuildContext context, double? value, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // 服务端没给 Content-Length 时 value 为 null，
              // 进度条自动变成不确定态的来回滚动
              LinearProgressIndicator(value: value),
              const SizedBox(height: 10),
              Text(
                value == null
                    ? '服务端没有告知文件大小，只能等它下完'
                    : '${(value * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 一组设置项：小标题 + 一张卡片。
class _Group extends StatelessWidget {
  const _Group({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: SectionLabel(icon: icon, title: title),
          ),
          SectionCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 16,
                      endIndent: 16,
                      color: AppColors.divider,
                    ),
                  children[i],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 点开弹单选面板的行。
class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.title,
    required this.value,
    required this.onTap,
    this.subtitle,
  });

  final String title;
  final String value;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _TitleBlock(title: title, subtitle: subtitle),
            ),
            const SizedBox(width: 10),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.enabled = true,
  });

  final String title;
  final bool value;
  final String? subtitle;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 10, 6),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _TitleBlock(
              title: title,
              subtitle: subtitle,
              dimmed: !enabled,
            ),
          ),
          Switch(
            value: value,
            onChanged: enabled ? onChanged : null,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

/// 高德 Key 一行：显示当前 Key 的来源，点开可以填自己的。
class _AmapKeyRow extends StatelessWidget {
  const _AmapKeyRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AmapRuntime runtime = AmapRuntime.instance;
    return ListenableBuilder(
      listenable: runtime.changes,
      builder: (BuildContext context, _) {
        final String hint;
        if (!runtime.hasKey) {
          hint = '还没有 Key，地图显示为本地示意图。点这里填自己的 Key';
        } else if (runtime.usingBuildKey) {
          hint = '正在用打包时内置的 Key。点这里可以换成自己的';
        } else {
          hint = '正在用你自己填的 Key（${AmapConfig.mask(runtime.effectiveKey)}）';
        }
        return _OptionRow(
          title: '高德地图 Key',
          subtitle: hint,
          value: runtime.hasKey ? (runtime.usingBuildKey ? '内置' : '已填') : '未配置',
          onTap: onTap,
        );
      },
    );
  }
}

/// 高德隐私声明的开关。没有可用 Key 时地图本来就走示意图，开关置灰。
class _PrivacyRow extends StatelessWidget {
  const _PrivacyRow({required this.onChanged});

  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final AmapRuntime runtime = AmapRuntime.instance;
    return ListenableBuilder(
      listenable: runtime.changes,
      builder: (BuildContext context, _) => _SwitchRow(
        title: '同意高德隐私声明',
        subtitle: runtime.hasKey
            ? '高德要求取得同意后才能加载地图；关掉会退回本地示意图'
            : '还没有可用的高德 Key，地图始终显示为本地示意图',
        value: runtime.privacyAgreed.value,
        enabled: runtime.hasKey,
        onChanged: onChanged,
      ),
    );
  }
}

/// 可以一键复制的只读行。值还没读到时显示占位，不给空白。
class _CopyRow extends StatelessWidget {
  const _CopyRow({
    required this.title,
    required this.value,
    required this.onCopy,
    this.hint,
  });

  final String title;
  final String? value;
  final String? hint;
  final Future<void> Function(String label, String value) onCopy;

  @override
  Widget build(BuildContext context) {
    final String? text = value;
    final bool ready = text != null && text.isNotEmpty;

    return InkWell(
      onTap: ready ? () => onCopy(title, text) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    ready ? text : '读取中…',
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      letterSpacing: 0.2,
                      color: ready
                          ? AppColors.textSecondary
                          : AppColors.textTertiary,
                    ),
                  ),
                  if (hint != null) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      hint!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (ready) ...<Widget>[
              const SizedBox(width: 8),
              const Icon(Icons.copy_outlined,
                  size: 17, color: AppColors.primary),
            ],
          ],
        ),
      ),
    );
  }
}

/// 只读的状态展示行。
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.title, required this.value, this.hint});

  final String title;
  final String value;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: <Widget>[
          Expanded(child: _TitleBlock(title: title, subtitle: hint)),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 点一下就执行动作的行。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
    this.busy = false,
  });

  final String title;
  final String? subtitle;
  final bool danger;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: <Widget>[
            Expanded(
              child: _TitleBlock(
                title: title,
                subtitle: subtitle,
                color: danger ? AppColors.danger : null,
              ),
            ),
            const SizedBox(width: 10),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            else
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.title,
    this.subtitle,
    this.color,
    this.dimmed = false,
  });

  final String title;
  final String? subtitle;
  final Color? color;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w500,
            color: color ??
                (dimmed ? AppColors.textTertiary : AppColors.textPrimary),
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
