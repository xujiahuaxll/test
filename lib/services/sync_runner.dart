import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/marker_repository.dart';
import '../models/location_mark.dart';
import 'cloud_sync.dart';
import 'media_store.dart';

/// 把「本地仓库 + 媒体目录 + 云端接口」串起来跑一次同步。
///
/// 拆成两步是故意的：[prepare] 只读不写，把差异算出来给用户看；
/// 用户选了策略之后才 [apply]。中间那一下确认很重要——三种策略里有两种
/// 会删数据，而删掉的照片和录音是找不回来的。
class SyncRunner {
  SyncRunner({
    required this.cloud,
    MarkerRepository? repository,
    MediaStore? mediaStore,
  })  : _repo = repository ?? MarkerRepository.instance,
        _media = mediaStore ?? MediaStore.instance;

  final CloudSync cloud;
  final MarkerRepository _repo;
  final MediaStore _media;

  /// 本机媒体的「内容指纹 -> 相对路径」。
  ///
  /// 有了它，从云端拿回来的记录如果引用的是本机已经有的那张图，
  /// 直接复用文件，不必再下载一遍。
  final Map<String, String> _localByHash = <String, String>{};

  /// 拉取云端数据并与本地比对。只读，不改任何东西。
  Future<SyncPreparation> prepare() async {
    final List<SyncMark> local = await _collectLocal();
    final List<SyncMark> server = await cloud.pull();
    return SyncPreparation(
      local: local,
      server: server,
      diff: SyncDiff.between(local, server),
    );
  }

  /// 按用户选的策略落地。
  Future<SyncOutcome> apply(
    SyncPreparation prep,
    SyncStrategy strategy,
  ) async {
    final SyncOutcome outcome = prep.diff.outcomeFor(strategy);
    final List<SyncMark> target =
        prep.diff.resolveLocal(strategy, prep.local, prep.server);

    // 本机要变成 target 的样子：先删掉不在里面的，再写入新的那些。
    final Set<String> targetIds = <String>{
      for (final SyncMark m in target) m.id,
    };
    final List<String> removed = <String>[
      for (final SyncMark m in prep.local)
        if (!targetIds.contains(m.id)) m.id,
    ];
    if (removed.isNotEmpty) await _repo.deleteAllByIds(removed);

    final Map<String, SyncMark> localById = <String, SyncMark>{
      for (final SyncMark m in prep.local) m.id: m,
    };
    final List<LocationMark> toWrite = <LocationMark>[];
    for (final SyncMark wanted in target) {
      final SyncMark? mine = localById[wanted.id];
      // 本机这条就是最终要的那条，原样留着，别白写一遍
      if (mine != null && !wanted.updatedAt.isAfter(mine.updatedAt)) continue;
      toWrite.add(await _materialize(wanted));
    }
    if (toWrite.isNotEmpty) await _repo.saveAll(toWrite);

    // 云端要不要更新：以服务端为主时不动它，另外两种要把结果推上去。
    if (strategy != SyncStrategy.serverWins) {
      final List<SyncMark> finalLocal = await _collectLocal();
      await _uploadMissingMedia(finalLocal);
      await cloud.push(finalLocal);
    }
    return outcome;
  }

  /// 把库里的标记连同媒体指纹一起读出来。
  Future<List<SyncMark>> _collectLocal() async {
    _localByHash.clear();
    final List<LocationMark> marks = await _repo.query();
    final List<SyncMark> out = <SyncMark>[];
    for (final LocationMark mark in marks) {
      final List<MediaRef> photos = <MediaRef>[];
      for (final String path in mark.photoPaths) {
        final MediaRef? ref = await _refFor(path);
        if (ref != null) photos.add(ref);
      }
      final String? audioPath = mark.audioPath;
      final MediaRef? audio =
          audioPath == null ? null : await _refFor(audioPath);
      out.add(SyncMark(mark: mark, photos: photos, audio: audio));
    }
    return out;
  }

  /// 算一个本地媒体文件的指纹。文件不在了就当这条记录没有它。
  Future<MediaRef?> _refFor(String relativePath) async {
    final File file = await _media.resolve(relativePath);
    if (!await file.exists()) return null;
    final String hash = await CloudSync.hashOf(file);
    _localByHash[hash] = relativePath;
    return MediaRef(
      sha256: hash,
      name: p.basename(relativePath),
      localPath: relativePath,
    );
  }

  /// 把一条云端记录变成能落库的本地记录：媒体该复用的复用、该下的下。
  Future<LocationMark> _materialize(SyncMark wanted) async {
    final List<String> photoPaths = <String>[];
    for (final MediaRef ref in wanted.photos) {
      final String? path = await _localize(ref, folder: 'photos', fallbackExt: '.jpg');
      if (path != null) photoPaths.add(path);
    }
    final MediaRef? audioRef = wanted.audio;
    final String? audioPath = audioRef == null
        ? null
        : await _localize(audioRef, folder: 'audio', fallbackExt: '.wav');

    return LocationMark(
      id: wanted.mark.id,
      name: wanted.mark.name,
      latitude: wanted.mark.latitude,
      longitude: wanted.mark.longitude,
      createdAt: wanted.mark.createdAt,
      updatedAt: wanted.mark.updatedAt,
      tags: wanted.mark.tags,
      address: wanted.mark.address,
      placeName: wanted.mark.placeName,
      accuracy: wanted.mark.accuracy,
      photoPaths: photoPaths,
      note: wanted.mark.note,
      audioPath: audioPath,
      audioDuration: wanted.mark.audioDuration,
      transcript: wanted.mark.transcript,
      waveform: wanted.mark.waveform,
    );
  }

  /// 拿到一个媒体文件的本地相对路径。
  ///
  /// 下载失败不让整次同步跟着失败——丢一张图，总好过用户点了半天
  /// 最后什么都没同步上。
  Future<String?> _localize(
    MediaRef ref, {
    required String folder,
    required String fallbackExt,
  }) async {
    if (ref.hasLocal) return ref.localPath;
    // 本机已经有同样内容的文件了，直接用，不必再下一遍
    final String? existing = _localByHash[ref.sha256];
    if (existing != null) return existing;
    if (ref.url.isEmpty) return null;

    try {
      final List<int> bytes = await cloud.download(ref.url);
      final String ext =
          p.extension(ref.name).isEmpty ? fallbackExt : p.extension(ref.name);
      final String path = await _media.saveBytes(
        bytes,
        folder: folder,
        extension: ext,
      );
      if (ref.sha256.isNotEmpty) _localByHash[ref.sha256] = path;
      return path;
    } on CloudFailure {
      return null;
    }
  }

  /// 把云端还没有的媒体传上去。先问一遍再传，省流量。
  Future<void> _uploadMissingMedia(List<SyncMark> marks) async {
    final List<String> hashes = <String>[
      for (final SyncMark m in marks) ...m.hashes,
    ];
    if (hashes.isEmpty) return;
    final Set<String> missing = await cloud.missingHashes(hashes);
    if (missing.isEmpty) return;

    for (final SyncMark mark in marks) {
      for (final MediaRef ref in <MediaRef>[
        ...mark.photos,
        if (mark.audio != null) mark.audio!,
      ]) {
        if (!missing.contains(ref.sha256) || !ref.hasLocal) continue;
        final File file = await _media.resolve(ref.localPath);
        if (!await file.exists()) continue;
        await cloud.upload(file, ref.sha256);
        // 同一份内容被多条记录引用时只传一次
        missing.remove(ref.sha256);
      }
    }
  }
}

/// [SyncRunner.prepare] 的结果：两边的数据加一份差异。
class SyncPreparation {
  const SyncPreparation({
    required this.local,
    required this.server,
    required this.diff,
  });

  final List<SyncMark> local;
  final List<SyncMark> server;
  final SyncDiff diff;
}
