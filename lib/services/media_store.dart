import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

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
  Future<({String relative, String absolute})> newAudioFile() async {
    final Directory dir = await _subDir('audio');
    final String relative = p.join('audio', '${_uuid.v4()}.m4a');
    return (relative: relative, absolute: p.join(dir.parent.path, relative));
  }

  Future<void> deleteFile(String relativePath) async {
    final File file = await resolve(relativePath);
    if (await file.exists()) {
      await file.delete();
    }
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
