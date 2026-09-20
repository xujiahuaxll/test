import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// 检查并安装新版本。
///
/// 服务端不在本项目范围内——这里只约定一个尽量好实现的接口：
/// 一次 GET，带上当前版本，返回最新版本和 APK 地址。字段名做容错，
/// 服务端少给几个字段也能用。
class UpgradeService {
  UpgradeService._();

  static final UpgradeService instance = UpgradeService._();

  /// 安装相关的原生能力走这条通道。
  static const MethodChannel channel =
      MethodChannel('location_marker/installer');

  /// 读本机当前版本。
  Future<AppVersion> currentVersion() async {
    final PackageInfo info = await PackageInfo.fromPlatform();
    return AppVersion(
      name: info.version,
      code: int.tryParse(info.buildNumber) ?? 0,
    );
  }

  /// 问服务端有没有新版本。[baseUrl] 为空时不该调到这里。
  Future<UpgradeInfo> check({
    required String baseUrl,
    required AppVersion current,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final Uri uri = buildCheckUri(baseUrl, current);
    final http.Response response;
    try {
      response = await http.get(uri).timeout(timeout);
    } on SocketException {
      throw const UpgradeFailure('连不上升级服务，请检查网址和网络');
    } catch (e) {
      throw UpgradeFailure('检查更新失败：$e');
    }
    if (response.statusCode != 200) {
      throw UpgradeFailure('升级服务返回 ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const UpgradeFailure('升级服务返回的不是 JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const UpgradeFailure('升级服务返回的 JSON 不是一个对象');
    }
    return UpgradeInfo.fromJson(decoded, current: current);
  }

  /// 拼检查地址。调用方给的网址可能自带查询串，这里合并而不是粗暴拼 `?`。
  static Uri buildCheckUri(String baseUrl, AppVersion current) {
    final Uri base = Uri.parse(baseUrl.trim());
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      'version': current.name,
      'build': '${current.code}',
      'platform': 'android',
    });
  }

  /// 下载 APK 到应用私有目录，[onProgress] 收到 0~1；
  /// 服务端没给 Content-Length 时收到 null（进度条显示为不确定态）。
  Future<File> download(
    String url, {
    void Function(double? progress)? onProgress,
  }) async {
    final Directory dir = await getApplicationSupportDirectory();
    final Directory target = Directory('${dir.path}/upgrade');
    if (!await target.exists()) await target.create(recursive: true);
    // 每次下载前清掉上一次的残留，别让半截文件占着空间
    for (final FileSystemEntity old in target.listSync()) {
      if (old is File) await old.delete();
    }

    final http.Client client = http.Client();
    try {
      final http.StreamedResponse response =
          await client.send(http.Request('GET', Uri.parse(url)));
      if (response.statusCode != 200) {
        throw UpgradeFailure('下载失败，服务器返回 ${response.statusCode}');
      }

      final File file = File('${target.path}/update.apk');
      final IOSink sink = file.openWrite();
      final int? total = response.contentLength;
      int received = 0;
      try {
        await for (final List<int> chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(total == null || total == 0 ? null : received / total);
        }
      } finally {
        await sink.close();
      }
      return file;
    } on SocketException {
      throw const UpgradeFailure('下载中断，请检查网络后重试');
    } finally {
      client.close();
    }
  }

  /// 唤起系统安装器。
  ///
  /// Android 8 起安装未知来源的包要用户单独授权，没授权就先把人送到那个
  /// 设置页——直接调安装会什么都不发生，用户只会以为按钮坏了。
  Future<InstallOutcome> install(File apk) async {
    try {
      final String? result = await channel.invokeMethod<String>(
        'installApk',
        <String, Object?>{'path': apk.path},
      );
      switch (result) {
        case 'started':
          return InstallOutcome.started;
        case 'needPermission':
          return InstallOutcome.needPermission;
        default:
          return InstallOutcome.failed;
      }
    } on PlatformException catch (e) {
      throw UpgradeFailure('唤起安装失败：${e.message ?? e.code}');
    } on MissingPluginException {
      throw const UpgradeFailure('当前平台不支持应用内安装');
    }
  }

  /// 比较两个版本号字符串。a 比 b 新返回正数，旧返回负数，一样返回 0。
  ///
  /// 按点分段逐段比数值，段数不等的短的一方补 0（`1.2` 等于 `1.2.0`）。
  /// 段里带字母时（`1.2.0-beta`）退回按字符串比，保证有个确定的结果，
  /// 不至于抛异常把整个检查流程带崩。
  static int compareVersion(String a, String b) {
    final List<String> left = _segments(a);
    final List<String> right = _segments(b);
    final int len = left.length > right.length ? left.length : right.length;
    for (int i = 0; i < len; i++) {
      final String l = i < left.length ? left[i] : '0';
      final String r = i < right.length ? right[i] : '0';
      final int? ln = int.tryParse(l);
      final int? rn = int.tryParse(r);
      final int cmp = (ln != null && rn != null)
          ? ln.compareTo(rn)
          : l.compareTo(r);
      if (cmp != 0) return cmp < 0 ? -1 : 1;
    }
    return 0;
  }

  static List<String> _segments(String raw) {
    final String trimmed = raw.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (trimmed.isEmpty) return <String>['0'];
    return trimmed.split('.');
  }
}

/// 本机当前的版本。
class AppVersion {
  const AppVersion({required this.name, required this.code});

  /// 「1.0.0」，pubspec 里 `version:` 加号前面那截。
  final String name;

  /// 加号后面那个整数。比版本名可靠：它必然单调递增。
  final int code;

  @override
  String toString() => '$name ($code)';
}

/// 服务端对一次检查的答复。
class UpgradeInfo {
  const UpgradeInfo({
    required this.hasUpdate,
    required this.version,
    required this.url,
    this.versionCode,
    this.note = '',
    this.force = false,
  });

  final bool hasUpdate;
  final String version;
  final String url;
  final int? versionCode;
  final String note;

  /// 服务端要求必须升级。界面据此不给「以后再说」。
  final bool force;

  bool get downloadable => url.isNotEmpty;

  /// 解析服务端的 JSON，并自己判定「这算不算新版本」。
  ///
  /// 不信任服务端自报的 hasUpdate：真正的依据是版本号比对，本地算一遍
  /// 才不会因为服务端写错一个布尔值就给用户推一个同版本的包。
  /// 有 versionCode 就优先用它比——它是整数，不会有 `1.10` 和 `1.9`
  /// 谁大的歧义。
  static UpgradeInfo fromJson(
    Map<String, Object?> json, {
    required AppVersion current,
  }) {
    String pick(List<String> keys) {
      for (final String key in keys) {
        final Object? value = json[key];
        if (value is String && value.trim().isNotEmpty) return value.trim();
        if (value is num) return '$value';
      }
      return '';
    }

    final String version = pick(<String>['version', 'versionName', 'latest']);
    final String url = pick(<String>['url', 'downloadUrl', 'apk', 'apkUrl']);
    final Object? rawCode =
        json['versionCode'] ?? json['build'] ?? json['buildNumber'];
    final int? code = rawCode is num
        ? rawCode.toInt()
        : (rawCode is String ? int.tryParse(rawCode) : null);

    final bool newer;
    if (code != null) {
      newer = code > current.code;
    } else if (version.isNotEmpty) {
      newer = UpgradeService.compareVersion(version, current.name) > 0;
    } else {
      newer = false;
    }

    return UpgradeInfo(
      hasUpdate: newer && url.isNotEmpty,
      version: version,
      versionCode: code,
      url: url,
      note: pick(<String>['note', 'releaseNote', 'changelog', 'description']),
      force: json['force'] == true || json['forceUpdate'] == true,
    );
  }
}

/// 唤起安装的结果。
enum InstallOutcome {
  /// 系统安装器已经弹出来了。
  started,

  /// 还没允许「安装未知应用」，已经把用户送去那个设置页。
  needPermission,

  /// 其它原因没起来。
  failed,
}

class UpgradeFailure implements Exception {
  const UpgradeFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
