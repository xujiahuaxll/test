import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/asr_service.dart';
import 'package:location_marker/services/recorder_service.dart';

void main() {
  group('模型要不要重新落地', () {
    // 模型必须从 assets 复制到应用目录才能用——ONNX Runtime 要文件路径，
    // 读不了 Flutter 的 assets。这里决定的是那次复制要不要重做。
    test('没复制过就得复制', () {
      expect(
        AsrService.shouldRestage(existingLength: null, assetLength: 81828675),
        isTrue,
      );
    });

    test('已经在了而且长度一致就跳过——78 MB 每次启动重抄一遍太亏', () {
      expect(
        AsrService.shouldRestage(
          existingLength: 81828675,
          assetLength: 81828675,
        ),
        isFalse,
      );
    });

    test('长度对不上要重来：上次多半是复制到一半被系统杀了', () {
      expect(
        AsrService.shouldRestage(
          existingLength: 40000000,
          assetLength: 81828675,
        ),
        isTrue,
      );
    });

    test('换了模型（长度变了）也要重来', () {
      expect(
        AsrService.shouldRestage(existingLength: 81828675, assetLength: 123),
        isTrue,
      );
    });

    test('空文件算没复制过', () {
      expect(
        AsrService.shouldRestage(existingLength: 0, assetLength: 81828675),
        isTrue,
      );
    });
  });

  group('录音格式', () {
    test('只有 WAV 能拿去离线识别，m4a 不行', () {
      // sherpa-onnx 吃的是 PCM，AAC 得先解码，本地没有解码器
      expect(RecordFormat.wav.transcribable, isTrue);
      expect(RecordFormat.m4a.transcribable, isFalse);
    });

    test('扩展名带点，能直接拼到文件名后面', () {
      for (final RecordFormat format in RecordFormat.values) {
        expect(format.extension, startsWith('.'));
      }
      expect(RecordFormat.wav.extension, '.wav');
      expect(RecordFormat.m4a.extension, '.m4a');
    });
  });
}
