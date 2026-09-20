import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/asr_service.dart';
import 'package:location_marker/utils/wav.dart';

/// 端到端跑一遍真正的离线识别。
///
/// 这里要挡的是那种「代码全对、analyze 全过、装到手机上一个字都出不来」的
/// 情况——模型类型填错、tokens 路径拼错、采样率没对上，编译期一个都看不出来，
/// 只有真跑一遍才知道。
///
/// 音频和模型由 scripts/fetch-asr-model.sh 下载，都不在 git 里；
/// 没下过就整组跳过，不让本地开发被卡住（CI 每次都会下）。
void main() {
  final File model = File('assets/asr/model.int8.onnx');
  final File sample = File('.asr-test/sample.wav');
  final String? nativeDir = _linuxNativeDir();
  final bool ready =
      model.existsSync() && sample.existsSync() && nativeDir != null;

  group(
    '离线识别真的跑得起来',
    () {
      late Directory stage;

      setUpAll(() {
        TestWidgetsFlutterBinding.ensureInitialized();
        stage = Directory.systemTemp.createTempSync('asr');
        AsrService.instance.overrideStageDirForTesting(stage);
        AsrService.instance.overrideNativeDirForTesting(nativeDir!);
      });

      tearDownAll(() async {
        await AsrService.instance.release();
        if (stage.existsSync()) stage.deleteSync(recursive: true);
      });

      test('模型能从 assets 落地到磁盘', () async {
        expect(await AsrService.instance.isAvailable(), isTrue);
        final File staged = File('${stage.path}/model.int8.onnx');
        expect(staged.existsSync(), isTrue);
        // 落地的那份必须和 assets 里一模一样大，缺一个字节模型都加载不了
        expect(staged.lengthSync(), model.lengthSync());
        expect(File('${stage.path}/tokens.txt').existsSync(), isTrue);
      });

      test('一段真录音能识别出中文', () async {
        final String text =
            await AsrService.instance.transcribeFile(sample.absolute.path);

        expect(text, isNotEmpty, reason: '一句完整的普通话不该识别成空串');
        // 不比对具体内容——小模型的输出会随版本变。只要求它确实吐出了汉字，
        // 而不是空串、乱码或者一串英文字母。
        expect(
          RegExp(r'[一-龥]').allMatches(text).length,
          greaterThan(5),
          reason: '识别结果里应当有成句的汉字，实际拿到：$text',
        );
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('第二次识别复用同一个常驻 isolate，不用重新加载模型', () async {
        final Stopwatch watch = Stopwatch()..start();
        final String again =
            await AsrService.instance.transcribeFile(sample.absolute.path);
        watch.stop();

        expect(again, isNotEmpty);
        // 重新加载 78 MB 的模型要好几秒。跑得比这快就说明缓存生效了。
        expect(
          watch.elapsed,
          lessThan(const Duration(seconds: 20)),
          reason: '第二次不该再花时间加载模型',
        );
      }, timeout: const Timeout(Duration(minutes: 2)));

      test('不是 WAV 的文件给出能看懂的提示，而不是崩掉', () async {
        final File fake = File('${stage.path}/fake.m4a')
          ..writeAsBytesSync(Uint8List.fromList(List<int>.filled(2048, 7)));
        await expectLater(
          AsrService.instance.transcribeFile(fake.path),
          throwsA(isA<AsrFailure>()),
        );
      });

      test('文件不存在也是 AsrFailure，不是 FileSystemException', () async {
        await expectLater(
          AsrService.instance.transcribeFile('${stage.path}/nope.wav'),
          throwsA(isA<AsrFailure>()),
        );
      });

      test('全是静音的录音不会抛异常，顶多识别不出东西', () async {
        // 一秒钟的绝对静音
        final Uint8List silence = Uint8List.fromList(<int>[
          ...Wav.header(
            sampleRate: 16000,
            channels: 1,
            bitsPerSample: 16,
            dataBytes: 32000,
          ),
          ...List<int>.filled(32000, 0),
        ]);
        final File quiet = File('${stage.path}/silence.wav')
          ..writeAsBytesSync(silence);
        await expectLater(
          AsrService.instance.transcribeFile(quiet.path),
          completion(isA<String>()),
        );
      }, timeout: const Timeout(Duration(minutes: 2)));
    },
    skip: ready
        ? false
        : '缺少模型、测试音频或本机的 sherpa 原生库，'
            '先跑 bash scripts/fetch-asr-model.sh',
  );
}

/// 找到本机 sherpa 原生库所在的目录。
///
/// 手机上不需要这一步：.so 在 APK 里，系统自己就能找到。但 flutter_tester
/// 是个桌面进程，.so 还躺在 pub-cache 里，得把路径指出来。
/// 找不到（比如不是 Linux）就让整组测试跳过。
String? _linuxNativeDir() {
  if (!Platform.isLinux) return null;
  try {
    final File config = File('.dart_tool/package_config.json');
    if (!config.existsSync()) return null;
    final Map<String, Object?> json =
        jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
    for (final Object? entry in json['packages'] as List<Object?>) {
      final Map<String, Object?> package = entry! as Map<String, Object?>;
      if (package['name'] != 'sherpa_onnx_linux') continue;
      final Directory root = Directory.fromUri(
        config.absolute.uri.resolve(package['rootUri']! as String),
      );
      for (final String arch in <String>['x64', 'aarch64']) {
        final Directory dir = Directory('${root.path}/linux/$arch');
        if (File('${dir.path}/libsherpa-onnx-c-api.so').existsSync()) {
          return dir.path;
        }
      }
    }
  } catch (_) {
    // 包配置读不出来就当没有，跳过这组测试即可
  }
  return null;
}
