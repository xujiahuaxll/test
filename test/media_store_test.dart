import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/media_store.dart';
import 'package:path/path.dart' as p;

/// 存储统计与孤儿文件清理：清理逻辑写错会误删用户的照片和录音。
void main() {
  late Directory tempDir;
  late MediaStore store;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_store_test');
    store = MediaStore.instance;
    store.overrideRootForTesting(tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// 在 photos/ 或 audio/ 下造一个指定大小的文件，返回相对路径。
  Future<String> makeFile(String sub, String name, int bytes) async {
    final Directory dir = Directory(p.join(tempDir.path, sub));
    await dir.create(recursive: true);
    final File file = File(p.join(dir.path, name));
    await file.writeAsBytes(List<int>.filled(bytes, 0));
    return p.join(sub, name);
  }

  test('目录还不存在时统计为空', () async {
    final MediaUsage usage = await store.usage();
    expect(usage.photoCount, 0);
    expect(usage.audioCount, 0);
    expect(usage.bytes, 0);
  });

  test('分别统计照片与录音的个数和总体积', () async {
    await makeFile('photos', 'a.jpg', 1000);
    await makeFile('photos', 'b.jpg', 2000);
    await makeFile('audio', 'v1.m4a', 500);

    final MediaUsage usage = await store.usage();
    expect(usage.photoCount, 2);
    expect(usage.audioCount, 1);
    expect(usage.bytes, 3500);
    expect(usage.fileCount, 3);
  });

  test('体积按大小换单位', () {
    expect(
      const MediaUsage(photoCount: 0, audioCount: 0, bytes: 512).readableSize,
      '512 B',
    );
    expect(
      const MediaUsage(photoCount: 0, audioCount: 0, bytes: 2048).readableSize,
      '2.0 KB',
    );
    expect(
      const MediaUsage(photoCount: 0, audioCount: 0, bytes: 3145728)
          .readableSize,
      '3.0 MB',
    );
  });

  test('只删没被引用的文件，被引用的一个都不动', () async {
    final String keptPhoto = await makeFile('photos', 'keep.jpg', 100);
    final String keptAudio = await makeFile('audio', 'keep.m4a', 100);
    final String orphanPhoto = await makeFile('photos', 'orphan.jpg', 300);
    final String orphanAudio = await makeFile('audio', 'orphan.m4a', 200);

    final MediaUsage removed =
        await store.removeOrphans(<String>{keptPhoto, keptAudio});

    expect(removed.photoCount, 1);
    expect(removed.audioCount, 1);
    expect(removed.bytes, 500);

    expect((await store.resolve(keptPhoto)).existsSync(), isTrue);
    expect((await store.resolve(keptAudio)).existsSync(), isTrue);
    expect((await store.resolve(orphanPhoto)).existsSync(), isFalse);
    expect((await store.resolve(orphanAudio)).existsSync(), isFalse);
  });

  test('引用集合为空时清空两个目录', () async {
    await makeFile('photos', 'a.jpg', 10);
    await makeFile('audio', 'v.m4a', 10);

    final MediaUsage removed = await store.removeOrphans(<String>{});
    expect(removed.fileCount, 2);
    expect((await store.usage()).fileCount, 0);
  });

  test('没有孤儿时什么都不删', () async {
    final String photo = await makeFile('photos', 'a.jpg', 10);
    final MediaUsage removed = await store.removeOrphans(<String>{photo});
    expect(removed.fileCount, 0);
    expect(removed.bytes, 0);
    expect((await store.usage()).fileCount, 1);
  });
}
