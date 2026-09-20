import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// photos/ 与 audio/ 的占用情况，给设置页展示。
class MediaUsage {
  const MediaUsage({
    required this.photoCount,
    required this.audioCount,
    required this.bytes,
  });

  final int photoCount;
  final int audioCount;
  final int bytes;

  int get fileCount => photoCount + audioCount;

  /// 人类可读的体积，保留一位小数。
  String get readableSize {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }
}

/// 照片与录音的本地落盘位置：应用私有目录下的 photos/ 与 audio/。
/// 数据库里只存相对路径，取用时再拼当前的应用目录
/// （iOS 沙盒目录会随版本变化，存绝对路径会失效）。
class MediaStore {
  MediaStore._();

  static final MediaStore instance = MediaStore._();

  static const Uuid _uuid = Uuid();

  Directory? _root;

  Future<Directory> get root async {
    final Directory? cached = _root;
    if (cached != null) return cached;
    final Directory dir = await getApplicationDocumentsDirectory();
    _root = dir;
    return dir;
  }

  /// 仅用于测试：把根目录指到临时目录。
  // ignore: use_setters_to_change_properties
  void overrideRootForTesting(Directory dir) => _root = dir;

  /// 启动时预热一次，之后界面就能同步拿到绝对路径去渲染图片。
  Future<void> warmUp() async => root;

  /// 同步取绝对路径，未预热时回落为相对路径（此时文件读不到，UI 会显示占位）。
  String absolute(String relativePath) {
    final Directory? dir = _root;
    return dir == null ? relativePath : p.join(dir.path, relativePath);
  }

  Future<File> resolve(String relativePath) async {
    final Directory dir = await root;
    return File(p.join(dir.path, relativePath));
  }

  Future<bool> exists(String relativePath) async =>
      (await resolve(relativePath)).exists();

  /// 把相机 / 相册给的临时文件复制进应用目录，返回相对路径。
  Future<String> importPhoto(String sourcePath) async {
    final Directory dir = await _subDir('photos');
    final String ext = p.extension(sourcePath).isEmpty
        ? '.jpg'
        : p.extension(sourcePath).toLowerCase();
    final String relative = p.join('photos', '${_uuid.v4()}$ext');
    await File(sourcePath).copy(p.join(dir.parent.path, relative));
    return relative;
  }

  /// 为一次新的录音分配文件路径，返回 (相对路径, 绝对路径)。
  ///
  /// [extension] 要和实际录出来的格式对上（.wav / .m4a）——播放器和离线
  /// 识别模型都会先看后缀，对不上就会被误导。
  Future<({String relative, String absolute})> newAudioFile({
    String extension = '.wav',
  }) async {
    final Directory dir = await _subDir('audio');
    final String ext = extension.startsWith('.') ? extension : '.$extension';
    final String relative = p.join('audio', '${_uuid.v4()}$ext');
    return (relative: relative, absolute: p.join(dir.parent.path, relative));
  }

  /// 把一段字节写进媒体目录，返回相对路径。
  ///
  /// 从云端拉回来的照片和录音走这里——它们不像相机给的那样先落成临时文件，
  /// 手上只有字节。
  Future<String> saveBytes(
    List<int> bytes, {
    required String folder,
    required String extension,
  }) async {
    final Directory dir = await _subDir(folder);
    final String ext = extension.startsWith('.') ? extension : '.$extension';
    final String relative = p.join(folder, '${_uuid.v4()}$ext');
    await File(p.join(dir.parent.path, relative)).writeAsBytes(bytes);
    return relative;
  }

  Future<void> deleteFile(String relativePath) async {
    final File file = await resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// 统计两个媒体目录的文件数与总体积。目录不存在时按空处理。
  Future<MediaUsage> usage() async {
    int photoCount = 0;
    int audioCount = 0;
    int bytes = 0;
    for (final String name in <String>['photos', 'audio']) {
      for (final File file in await _filesIn(name)) {
        bytes += await file.length();
        if (name == 'photos') {
          photoCount++;
        } else {
          audioCount++;
        }
      }
    }
    return MediaUsage(
      photoCount: photoCount,
      audioCount: audioCount,
      bytes: bytes,
    );
  }

  /// 删掉库里已经没有引用的媒体文件。
  ///
  /// 删除标记时中途失败、或早期版本留下的文件会变成孤儿，一直占着空间。
  /// [referenced] 传数据库里还在用的相对路径集合。
  Future<MediaUsage> removeOrphans(Set<String> referenced) async {
    final Directory dir = await root;
    int photoCount = 0;
    int audioCount = 0;
    int bytes = 0;
    for (final String name in <String>['photos', 'audio']) {
      for (final File file in await _filesIn(name)) {
        // 统一成数据库里那种 `photos/xxx.jpg` 的相对写法再比对。
        final String relative = p.relative(file.path, from: dir.path);
        if (referenced.contains(relative)) continue;
        final int size = await file.length();
        try {
          await file.delete();
        } catch (_) {
          // 删不掉就跳过，不计入释放的空间。
          continue;
        }
        bytes += size;
        if (name == 'photos') {
          photoCount++;
        } else {
          audioCount++;
        }
      }
    }
    return MediaUsage(
      photoCount: photoCount,
      audioCount: audioCount,
      bytes: bytes,
    );
  }

  Future<List<File>> _filesIn(String name) async {
    final Directory dir = await root;
    final Directory sub = Directory(p.join(dir.path, name));
    if (!await sub.exists()) return <File>[];
    return sub
        .listSync(followLinks: false)
        .whereType<File>()
        .toList(growable: false);
  }

  Future<Directory> _subDir(String name) async {
    final Directory dir = await root;
    final Directory sub = Directory(p.join(dir.path, name));
    if (!await sub.exists()) {
      await sub.create(recursive: true);
    }
    return sub;
  }
}
