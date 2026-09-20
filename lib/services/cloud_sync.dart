import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../models/location_mark.dart';

/// 同步策略。三种的删除/新增口径完全不同，界面要按选中的那种改措辞。
enum SyncStrategy {
  /// 本地变成服务端的样子：服务端没有的本地要删掉。
  serverWins('以服务端为主'),

  /// 服务端变成本地的样子：本地没有的云端要删掉。
  localWins('以本地为主'),

  /// 双方取并集，谁都不删。同一条记录取改动时间新的那一版。
  merge('合并');

  const SyncStrategy(this.label);

  final String label;
}

/// 从别人的服务端拿来的 JSON 一律用这几个取值，不做硬转换。
///
/// `as List<Object?>?` 这类写法在字段类型对不上时会直接抛，而这份 JSON
/// 是用户自己的服务端产出的——写错一个字段就让整次同步失败，太脆了。
Object? _at(Map<Object?, Object?> raw, String key) => raw[key];

String _text(Object? v) {
  if (v is String) return v.trim();
  if (v is num || v is bool) return '$v';
  return '';
}

String? _textOrNull(Object? v) {
  final String t = _text(v);
  return t.isEmpty ? null : t;
}

double? _number(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v.trim());
  return null;
}

int? _integer(Object? v) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v.trim());
  return null;
}

List<Object?> _list(Object? v) => v is List<Object?> ? v : const <Object?>[];

/// 一条记录的媒体文件：照片或录音。
///
/// 按内容的 sha256 寻址——同一张图不管被几条记录引用、传过多少次，
/// 服务端只要存一份，客户端也只要传一次。
class MediaRef {
  const MediaRef({
    required this.sha256,
    required this.name,
    this.url = '',
    this.localPath = '',
  });

  final String sha256;

  /// 文件名（含扩展名），下载回来时据此决定存成什么。
  final String name;

  /// 服务端给的下载地址。push 的时候可以为空。
  final String url;

  /// 本机的相对路径。从服务端拉下来的记录这一项为空，下载后才填上。
  final String localPath;

  bool get hasLocal => localPath.isNotEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'sha256': sha256,
        'name': name,
        if (url.isNotEmpty) 'url': url,
      };

  static MediaRef? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final String hash = _text(_at(raw, 'sha256'));
    final String name = _text(_at(raw, 'name'));
    if (hash.isEmpty && name.isEmpty) return null;
    return MediaRef(
      sha256: hash,
      name: name,
      url: _text(_at(raw, 'url')),
    );
  }

  MediaRef withLocalPath(String path) => MediaRef(
        sha256: sha256,
        name: name,
        url: url,
        localPath: path,
      );
}

/// 一条可同步的标记：本地的 [LocationMark] 加上媒体的内容指纹。
///
/// 不直接复用 LocationMark.toRow()：那是 SQLite 的行格式，标签和照片
/// 在另外两张子表里、波形是逗号分隔的字符串，拿去当 JSON 传对方没法用。
class SyncMark {
  const SyncMark({
    required this.mark,
    this.photos = const <MediaRef>[],
    this.audio,
  });

  final LocationMark mark;
  final List<MediaRef> photos;
  final MediaRef? audio;

  String get id => mark.id;

  DateTime get updatedAt => mark.updatedAt;

  /// 这条记录引用到的全部媒体指纹。
  List<String> get hashes => <String>[
        for (final MediaRef p in photos)
          if (p.sha256.isNotEmpty) p.sha256,
        if (audio != null && audio!.sha256.isNotEmpty) audio!.sha256,
      ];

  Map<String, Object?> toJson() => <String, Object?>{
        'id': mark.id,
        'name': mark.name,
        'latitude': mark.latitude,
        'longitude': mark.longitude,
        'placeName': mark.placeName,
        'address': mark.address,
        'accuracy': mark.accuracy,
        'note': mark.note,
        'transcript': mark.transcript,
        'tags': mark.tags,
        'waveform': mark.waveform,
        'audioDurationMs': mark.audioDuration?.inMilliseconds,
        'createdAt': mark.createdAt.millisecondsSinceEpoch,
        'updatedAt': mark.updatedAt.millisecondsSinceEpoch,
        'photos': <Object?>[for (final MediaRef p in photos) p.toJson()],
        'audio': audio?.toJson(),
      };

  /// 从服务端的 JSON 还原。
  ///
  /// 容错要足：这份 JSON 是别人的服务端产出的，缺字段、类型写错都可能。
  /// 只有 id 是硬要求——没有它这条记录就没法参与按 GUID 的比对。
  static SyncMark? fromJson(Object? raw) {
    if (raw is! Map<Object?, Object?>) return null;
    final String id = _text(_at(raw, 'id'));
    if (id.isEmpty) return null;

    final int? durationMs = _integer(_at(raw, 'audioDurationMs'));
    final int now = DateTime.now().millisecondsSinceEpoch;

    return SyncMark(
      mark: LocationMark(
        id: id,
        name: _text(_at(raw, 'name')),
        latitude: _number(_at(raw, 'latitude')) ?? 0,
        longitude: _number(_at(raw, 'longitude')) ?? 0,
        placeName: _textOrNull(_at(raw, 'placeName')),
        address: _textOrNull(_at(raw, 'address')),
        accuracy: _number(_at(raw, 'accuracy')),
        note: _text(_at(raw, 'note')),
        transcript: _textOrNull(_at(raw, 'transcript')),
        tags: <String>[
          for (final Object? t in _list(_at(raw, 'tags')))
            if (_text(t).isNotEmpty) _text(t),
        ],
        waveform: <double>[
          for (final Object? v in _list(_at(raw, 'waveform')))
            if (_number(v) case final double d) d,
        ],
        audioDuration:
            durationMs == null ? null : Duration(milliseconds: durationMs),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          _integer(_at(raw, 'createdAt')) ?? now,
        ),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
          _integer(_at(raw, 'updatedAt')) ?? now,
        ),
      ),
      photos: <MediaRef>[
        for (final Object? p in _list(_at(raw, 'photos')))
          if (MediaRef.fromJson(p) case final MediaRef ref) ref,
      ],
      audio: MediaRef.fromJson(_at(raw, 'audio')),
    );
  }
}

/// 本地与服务端按 GUID 比对的结果。
class SyncDiff {
  const SyncDiff({
    required this.onlyLocal,
    required this.onlyServer,
    required this.localNewer,
    required this.serverNewer,
  });

  /// 只有本机有的。
  final List<SyncMark> onlyLocal;

  /// 只有服务端有的。
  final List<SyncMark> onlyServer;

  /// 两边都有，但本机这版改得更晚。
  final List<SyncMark> localNewer;

  /// 两边都有，但服务端那版改得更晚。
  final List<SyncMark> serverNewer;

  bool get isEmpty =>
      onlyLocal.isEmpty &&
      onlyServer.isEmpty &&
      localNewer.isEmpty &&
      serverNewer.isEmpty;

  /// 按 GUID 比对。两边都有时按 updatedAt 判断谁更新，
  /// 完全相同的时间算作「没变化」，不进任何一边。
  static SyncDiff between(List<SyncMark> local, List<SyncMark> server) {
    final Map<String, SyncMark> localById = <String, SyncMark>{
      for (final SyncMark m in local) m.id: m,
    };
    final Map<String, SyncMark> serverById = <String, SyncMark>{
      for (final SyncMark m in server) m.id: m,
    };

    final List<SyncMark> onlyLocal = <SyncMark>[];
    final List<SyncMark> localNewer = <SyncMark>[];
    for (final SyncMark m in local) {
      final SyncMark? other = serverById[m.id];
      if (other == null) {
        onlyLocal.add(m);
      } else if (m.updatedAt.isAfter(other.updatedAt)) {
        localNewer.add(m);
      }
    }

    final List<SyncMark> onlyServer = <SyncMark>[];
    final List<SyncMark> serverNewer = <SyncMark>[];
    for (final SyncMark m in server) {
      final SyncMark? other = localById[m.id];
      if (other == null) {
        onlyServer.add(m);
      } else if (m.updatedAt.isAfter(other.updatedAt)) {
        serverNewer.add(m);
      }
    }

    return SyncDiff(
      onlyLocal: onlyLocal,
      onlyServer: onlyServer,
      localNewer: localNewer,
      serverNewer: serverNewer,
    );
  }

  /// 选了某个策略之后，本机会发生什么。
  SyncOutcome outcomeFor(SyncStrategy strategy) {
    switch (strategy) {
      case SyncStrategy.serverWins:
        return SyncOutcome(
          localAdded: onlyServer.length,
          localDeleted: onlyLocal.length,
          localUpdated: serverNewer.length,
          remoteAdded: 0,
          remoteDeleted: 0,
          remoteUpdated: 0,
        );
      case SyncStrategy.localWins:
        return SyncOutcome(
          localAdded: 0,
          localDeleted: 0,
          localUpdated: 0,
          remoteAdded: onlyLocal.length,
          remoteDeleted: onlyServer.length,
          remoteUpdated: localNewer.length,
        );
      case SyncStrategy.merge:
        // 并集，谁都不删；同一条取改动时间新的那版
        return SyncOutcome(
          localAdded: onlyServer.length,
          localDeleted: 0,
          localUpdated: serverNewer.length,
          remoteAdded: onlyLocal.length,
          remoteDeleted: 0,
          remoteUpdated: localNewer.length,
        );
    }
  }

  /// 按策略算出「本机最终应该是哪些记录」。
  List<SyncMark> resolveLocal(SyncStrategy strategy, List<SyncMark> local,
      List<SyncMark> server) {
    switch (strategy) {
      case SyncStrategy.serverWins:
        return List<SyncMark>.of(server);
      case SyncStrategy.localWins:
        return List<SyncMark>.of(local);
      case SyncStrategy.merge:
        final Map<String, SyncMark> merged = <String, SyncMark>{
          for (final SyncMark m in local) m.id: m,
        };
        for (final SyncMark m in server) {
          final SyncMark? mine = merged[m.id];
          if (mine == null || m.updatedAt.isAfter(mine.updatedAt)) {
            merged[m.id] = m;
          }
        }
        return merged.values.toList();
    }
  }
}

/// 一次同步会改动多少东西。界面拿它生成那三段措辞各不相同的说明。
class SyncOutcome {
  const SyncOutcome({
    required this.localAdded,
    required this.localDeleted,
    required this.localUpdated,
    required this.remoteAdded,
    required this.remoteDeleted,
    required this.remoteUpdated,
  });

  final int localAdded;
  final int localDeleted;
  final int localUpdated;
  final int remoteAdded;
  final int remoteDeleted;
  final int remoteUpdated;

  bool get changesNothing =>
      localAdded == 0 &&
      localDeleted == 0 &&
      localUpdated == 0 &&
      remoteAdded == 0 &&
      remoteDeleted == 0 &&
      remoteUpdated == 0;

  /// 一句给用户看的话。删除单独说，因为那是不可逆的。
  String describe() {
    final List<String> parts = <String>[];
    void add(String where, int added, int deleted, int updated) {
      final List<String> bits = <String>[
        if (added > 0) '新增 $added 条',
        if (updated > 0) '更新 $updated 条',
        if (deleted > 0) '删除 $deleted 条',
      ];
      if (bits.isNotEmpty) parts.add('$where${bits.join('、')}');
    }

    add('本机', localAdded, localDeleted, localUpdated);
    add('云端', remoteAdded, remoteDeleted, remoteUpdated);
    return parts.isEmpty ? '两边已经一致，不需要改动' : parts.join('；');
  }
}

/// 和用户自己的服务端说话。协议见 docs/api.md。
class CloudSync {
  CloudSync({
    required this.baseUrl,
    required this.account,
    required this.password,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String baseUrl;
  final String account;
  final String password;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 30);

  void close() => _client.close();

  Map<String, Object?> _auth(Map<String, Object?> extra) => <String, Object?>{
        'account': account,
        'password': password,
        ...extra,
      };

  Future<Map<String, Object?>> _post(Map<String, Object?> body) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(baseUrl.trim()),
            headers: const <String, String>{
              'Content-Type': 'application/json; charset=utf-8',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on SocketException {
      throw const CloudFailure('连不上云端服务，请检查网址和网络');
    } catch (e) {
      throw CloudFailure('请求失败：$e');
    }

    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const CloudFailure('账号或密码不对');
    }
    if (response.statusCode != 200) {
      throw CloudFailure('云端服务返回 ${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw const CloudFailure('云端返回的不是 JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const CloudFailure('云端返回的 JSON 不是一个对象');
    }
    if (decoded['ok'] == false) {
      final String message = _text(decoded['message']);
      throw CloudFailure(message.isEmpty ? '云端拒绝了这次请求' : message);
    }
    return decoded;
  }

  /// 拉取服务端全量。
  Future<List<SyncMark>> pull() async {
    final Map<String, Object?> body =
        await _post(_auth(<String, Object?>{'action': 'pull'}));
    return parseMarkers(body['markers']);
  }

  /// 覆盖保存。服务端按这份数据整体替换这个账号的记录。
  Future<void> push(List<SyncMark> marks) async {
    await _post(_auth(<String, Object?>{
      'action': 'push',
      'markers': <Object?>[for (final SyncMark m in marks) m.toJson()],
    }));
  }

  /// 问服务端这些指纹里哪些它还没有，只传缺的。
  Future<Set<String>> missingHashes(List<String> hashes) async {
    if (hashes.isEmpty) return <String>{};
    final Map<String, Object?> body = await _post(_auth(<String, Object?>{
      'action': 'missing',
      'hashes': hashes.toSet().toList(),
    }));
    return <String>{
      for (final Object? h in _list(body['missing']))
        if (_text(h).isNotEmpty) _text(h),
    };
  }

  /// 上传一个媒体文件，返回服务端给的下载地址。
  Future<String> upload(File file, String sha256Hex) async {
    final Uri uri = Uri.parse(baseUrl.trim()).replace(
      queryParameters: <String, String>{
        ...Uri.parse(baseUrl.trim()).queryParameters,
        'action': 'upload',
      },
    );
    final http.MultipartRequest request = http.MultipartRequest('POST', uri)
      ..fields['account'] = account
      ..fields['password'] = password
      ..fields['sha256'] = sha256Hex
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_timeout);
    } on SocketException {
      throw const CloudFailure('上传中断，请检查网络');
    }
    final http.Response response = await http.Response.fromStream(streamed);
    if (response.statusCode != 200) {
      throw CloudFailure('上传失败，服务器返回 ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, Object?> || decoded['ok'] == false) {
      throw const CloudFailure('上传失败，云端没有确认');
    }
    return _text(decoded['url']);
  }

  /// 下载一个媒体文件的字节。
  Future<List<int>> download(String url) async {
    final http.Response response;
    try {
      response = await _client.get(Uri.parse(url)).timeout(_timeout);
    } on SocketException {
      throw const CloudFailure('下载中断，请检查网络');
    }
    if (response.statusCode != 200) {
      throw CloudFailure('下载失败，服务器返回 ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  static List<SyncMark> parseMarkers(Object? raw) => <SyncMark>[
        for (final Object? item in _list(raw))
          if (SyncMark.fromJson(item) case final SyncMark m) m,
      ];

  /// 算一个文件的内容指纹。同一份内容在哪台手机上算出来都一样，
  /// 服务端据此天然去重。
  static Future<String> hashOf(File file) async {
    final Digest digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}

class CloudFailure implements Exception {
  const CloudFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
