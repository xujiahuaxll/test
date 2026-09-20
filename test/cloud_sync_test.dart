import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/models/location_mark.dart';
import 'package:location_marker/services/cloud_sync.dart';

SyncMark markOf(
  String id, {
  String name = '某地',
  int updatedAtMs = 1000,
  List<String> tags = const <String>[],
  List<MediaRef> photos = const <MediaRef>[],
  MediaRef? audio,
}) {
  return SyncMark(
    mark: LocationMark(
      id: id,
      name: name,
      latitude: 39.9,
      longitude: 116.4,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtMs),
      tags: tags,
    ),
    photos: photos,
    audio: audio,
  );
}

void main() {
  group('按 GUID 比对', () {
    test('分出「只有本地」「只有云端」两堆', () {
      final SyncDiff diff = SyncDiff.between(
        <SyncMark>[markOf('a'), markOf('b')],
        <SyncMark>[markOf('b'), markOf('c')],
      );
      expect(diff.onlyLocal.map((SyncMark m) => m.id), <String>['a']);
      expect(diff.onlyServer.map((SyncMark m) => m.id), <String>['c']);
    });

    test('两边都有时按改动时间分出谁更新', () {
      final SyncDiff diff = SyncDiff.between(
        <SyncMark>[markOf('a', updatedAtMs: 2000), markOf('b', updatedAtMs: 1)],
        <SyncMark>[markOf('a', updatedAtMs: 1000), markOf('b', updatedAtMs: 500)],
      );
      expect(diff.localNewer.map((SyncMark m) => m.id), <String>['a']);
      expect(diff.serverNewer.map((SyncMark m) => m.id), <String>['b']);
    });

    test('时间完全一样就当没变化，不进任何一堆', () {
      final SyncDiff diff = SyncDiff.between(
        <SyncMark>[markOf('a', updatedAtMs: 1000)],
        <SyncMark>[markOf('a', updatedAtMs: 1000)],
      );
      expect(diff.isEmpty, isTrue);
    });

    test('两边都空', () {
      expect(
        SyncDiff.between(const <SyncMark>[], const <SyncMark>[]).isEmpty,
        isTrue,
      );
    });
  });

  group('三种策略的后果各不相同', () {
    // 本地有 a、b(新)，云端有 b(旧)、c
    final SyncDiff diff = SyncDiff.between(
      <SyncMark>[markOf('a'), markOf('b', updatedAtMs: 2000)],
      <SyncMark>[markOf('b', updatedAtMs: 1000), markOf('c')],
    );

    test('以服务端为主：本地新增 1、删除 1，云端不动', () {
      final SyncOutcome o = diff.outcomeFor(SyncStrategy.serverWins);
      expect(o.localAdded, 1, reason: 'c 要下来');
      expect(o.localDeleted, 1, reason: 'a 云端没有，要删掉');
      expect(o.remoteAdded, 0);
      expect(o.remoteDeleted, 0);
    });

    test('以本地为主：云端新增 1、删除 1，本地不动', () {
      final SyncOutcome o = diff.outcomeFor(SyncStrategy.localWins);
      expect(o.remoteAdded, 1, reason: 'a 要传上去');
      expect(o.remoteDeleted, 1, reason: 'c 本地没有，云端要删掉');
      expect(o.localAdded, 0);
      expect(o.localDeleted, 0);
    });

    test('合并：双方各新增，谁都不删', () {
      final SyncOutcome o = diff.outcomeFor(SyncStrategy.merge);
      expect(o.localAdded, 1);
      expect(o.remoteAdded, 1);
      expect(o.localDeleted, 0);
      expect(o.remoteDeleted, 0);
    });

    test('措辞里带上删除，而且三种说法不一样', () {
      final String server = diff.outcomeFor(SyncStrategy.serverWins).describe();
      final String local = diff.outcomeFor(SyncStrategy.localWins).describe();
      final String merge = diff.outcomeFor(SyncStrategy.merge).describe();

      expect(server, contains('删除'));
      expect(local, contains('删除'));
      expect(merge, isNot(contains('删除')));
      expect(<String>{server, local, merge}, hasLength(3));
    });

    test('两边一致时说「不需要改动」，不要报一串 0', () {
      final SyncDiff same = SyncDiff.between(
        <SyncMark>[markOf('a')],
        <SyncMark>[markOf('a')],
      );
      final SyncOutcome o = same.outcomeFor(SyncStrategy.merge);
      expect(o.changesNothing, isTrue);
      expect(o.describe(), '两边已经一致，不需要改动');
    });
  });

  group('算出本机最终该有哪些记录', () {
    final List<SyncMark> local = <SyncMark>[
      markOf('a'),
      markOf('b', name: '本地版', updatedAtMs: 2000),
    ];
    final List<SyncMark> server = <SyncMark>[
      markOf('b', name: '云端版', updatedAtMs: 1000),
      markOf('c'),
    ];
    final SyncDiff diff = SyncDiff.between(local, server);

    test('以服务端为主就整份换成服务端的', () {
      final List<SyncMark> out =
          diff.resolveLocal(SyncStrategy.serverWins, local, server);
      expect(out.map((SyncMark m) => m.id).toSet(), <String>{'b', 'c'});
    });

    test('以本地为主就原样不动', () {
      final List<SyncMark> out =
          diff.resolveLocal(SyncStrategy.localWins, local, server);
      expect(out.map((SyncMark m) => m.id).toSet(), <String>{'a', 'b'});
    });

    test('合并取并集，同一条取改动时间新的那版', () {
      final List<SyncMark> out =
          diff.resolveLocal(SyncStrategy.merge, local, server);
      expect(out.map((SyncMark m) => m.id).toSet(), <String>{'a', 'b', 'c'});
      final SyncMark b = out.firstWhere((SyncMark m) => m.id == 'b');
      expect(b.mark.name, '本地版', reason: '本地那版改得更晚');
    });

    test('云端那版更新时合并要采用云端的', () {
      final List<SyncMark> l = <SyncMark>[markOf('b', name: '旧', updatedAtMs: 1)];
      final List<SyncMark> r = <SyncMark>[markOf('b', name: '新', updatedAtMs: 9)];
      final List<SyncMark> out =
          SyncDiff.between(l, r).resolveLocal(SyncStrategy.merge, l, r);
      expect(out.single.mark.name, '新');
    });
  });

  group('JSON 往返', () {
    test('字段来回一趟不丢', () {
      final SyncMark original = SyncMark(
        mark: LocationMark(
          id: 'uuid-1',
          name: '老张家的面馆',
          latitude: 39.908722,
          longitude: 116.397499,
          createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
          tags: const <String>['美食', '打卡'],
          address: '北京市大兴区天河北路5号',
          placeName: '中铁吉盛物流大厦',
          accuracy: 12.5,
          note: '二楼，牛肉面加蛋',
          transcript: '转写出来的文字',
          audioDuration: const Duration(seconds: 12),
          waveform: const <double>[0.4, 0.9],
        ),
        photos: const <MediaRef>[
          MediaRef(sha256: 'hash1', name: 'a.jpg', url: 'https://x/a.jpg'),
        ],
        audio: const MediaRef(sha256: 'hash2', name: 'b.m4a'),
      );

      final SyncMark? back = SyncMark.fromJson(original.toJson());
      expect(back, isNotNull);
      expect(back!.mark.id, 'uuid-1');
      expect(back.mark.name, '老张家的面馆');
      expect(back.mark.latitude, closeTo(39.908722, 1e-9));
      expect(back.mark.tags, <String>['美食', '打卡']);
      expect(back.mark.placeName, '中铁吉盛物流大厦');
      expect(back.mark.accuracy, 12.5);
      expect(back.mark.transcript, '转写出来的文字');
      expect(back.mark.audioDuration, const Duration(seconds: 12));
      expect(back.mark.waveform, <double>[0.4, 0.9]);
      expect(back.mark.createdAt.millisecondsSinceEpoch, 1000);
      expect(back.mark.updatedAt.millisecondsSinceEpoch, 2000);
      expect(back.photos.single.sha256, 'hash1');
      expect(back.photos.single.url, 'https://x/a.jpg');
      expect(back.audio!.name, 'b.m4a');
    });

    test('没有 id 的记录直接丢掉——它没法参与按 GUID 的比对', () {
      expect(SyncMark.fromJson(<String, Object?>{'name': '没有 id'}), isNull);
      expect(SyncMark.fromJson(<String, Object?>{'id': '  '}), isNull);
      expect(SyncMark.fromJson('不是对象'), isNull);
    });

    test('服务端少给字段也能还原，不抛异常', () {
      final SyncMark? m = SyncMark.fromJson(<String, Object?>{'id': 'x'});
      expect(m, isNotNull);
      expect(m!.mark.name, '');
      expect(m.mark.latitude, 0);
      expect(m.mark.tags, isEmpty);
      expect(m.photos, isEmpty);
      expect(m.audio, isNull);
    });

    test('字段类型写错也扛得住', () {
      final SyncMark? m = SyncMark.fromJson(<String, Object?>{
        'id': 'x',
        'latitude': '不是数字',
        'tags': '不是数组',
        'photos': <Object?>['不是对象', 42],
        'audioDurationMs': '3000',
      });
      expect(m, isNotNull);
      expect(m!.mark.latitude, 0);
      expect(m.mark.tags, isEmpty);
      expect(m.photos, isEmpty);
      expect(m.mark.audioDuration, const Duration(seconds: 3));
    });

    test('解析整份列表时跳过坏条目，不是整份作废', () {
      final List<SyncMark> out = CloudSync.parseMarkers(<Object?>[
        <String, Object?>{'id': 'good'},
        <String, Object?>{'name': '没有 id'},
        null,
      ]);
      expect(out.map((SyncMark m) => m.id), <String>['good']);
    });
  });

  group('媒体指纹', () {
    test('列出一条记录引用到的全部指纹', () {
      final SyncMark m = markOf(
        'a',
        photos: const <MediaRef>[
          MediaRef(sha256: 'p1', name: '1.jpg'),
          MediaRef(sha256: 'p2', name: '2.jpg'),
        ],
        audio: const MediaRef(sha256: 'a1', name: 'a.m4a'),
      );
      expect(m.hashes, <String>['p1', 'p2', 'a1']);
    });

    test('指纹为空的不算数——那是本地文件已经不在了', () {
      final SyncMark m = markOf(
        'a',
        photos: const <MediaRef>[MediaRef(sha256: '', name: '1.jpg')],
      );
      expect(m.hashes, isEmpty);
    });
  });
}
