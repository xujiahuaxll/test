import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/utils/wav.dart';

/// 拼一个 16 位单声道的 WAV 文件。
Uint8List buildWav(
  List<int> samples, {
  int sampleRate = 16000,
  int channels = 1,
}) {
  final Uint8List body = Uint8List(samples.length * 2);
  final ByteData view = ByteData.sublistView(body);
  for (int i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  final Uint8List head = Wav.header(
    sampleRate: sampleRate,
    channels: channels,
    bitsPerSample: 16,
    dataBytes: body.length,
  );
  return Uint8List.fromList(<int>[...head, ...body]);
}

void main() {
  group('拼 WAV 头', () {
    test('该是 44 字节，RIFF/WAVE/fmt/data 都在该在的位置', () {
      final Uint8List head = Wav.header(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 320,
      );
      expect(head, hasLength(44));
      expect(String.fromCharCodes(head, 0, 4), 'RIFF');
      expect(String.fromCharCodes(head, 8, 12), 'WAVE');
      expect(String.fromCharCodes(head, 12, 16), 'fmt ');
      expect(String.fromCharCodes(head, 36, 40), 'data');
    });

    test('长度字段算对：RIFF 是 36 + 数据长度', () {
      final ByteData head = ByteData.sublistView(
        Wav.header(
          sampleRate: 16000,
          channels: 1,
          bitsPerSample: 16,
          dataBytes: 1000,
        ),
      );
      expect(head.getUint32(4, Endian.little), 1036);
      expect(head.getUint32(40, Endian.little), 1000);
    });

    test('字节率和块对齐按声道与位深算', () {
      final ByteData head = ByteData.sublistView(
        Wav.header(
          sampleRate: 44100,
          channels: 2,
          bitsPerSample: 16,
          dataBytes: 0,
        ),
      );
      // blockAlign = 2 声道 × 2 字节
      expect(head.getUint16(32, Endian.little), 4);
      expect(head.getUint32(28, Endian.little), 44100 * 4);
    });
  });

  group('解 WAV', () {
    test('16 位采样归一化到 -1~1', () {
      final WavAudio audio = Wav.decode(buildWav(<int>[0, 16384, -32768, 32767]));
      expect(audio.sampleRate, 16000);
      expect(audio.channels, 1);
      expect(audio.samples[0], 0);
      expect(audio.samples[1], closeTo(0.5, 1e-4));
      expect(audio.samples[2], closeTo(-1.0, 1e-4));
      expect(audio.samples[3], closeTo(1.0, 1e-3));
    });

    test('双声道混成单声道', () {
      // 左 1.0 右 -1.0，混出来应该是 0
      final Uint8List bytes =
          buildWav(<int>[32767, -32767, 16384, 16384], channels: 2);
      final WavAudio audio = Wav.decode(bytes);
      expect(audio.channels, 2);
      expect(audio.samples, hasLength(2));
      expect(audio.samples[0], closeTo(0, 1e-3));
      expect(audio.samples[1], closeTo(0.5, 1e-3));
    });

    test('fmt 和 data 之间夹着别的块也能找到数据', () {
      // 真实文件里常有 LIST 块。按固定偏移 44 取数据的写法碰上这个就废了。
      final Uint8List plain = buildWav(<int>[1000, -1000]);
      final List<int> withList = <int>[
        ...plain.sublist(0, 36),
        ...'LIST'.codeUnits,
        4, 0, 0, 0,
        9, 9, 9, 9,
        ...plain.sublist(36),
      ];
      final WavAudio audio = Wav.decode(Uint8List.fromList(withList));
      expect(audio.samples, hasLength(2));
      expect(audio.samples[0], closeTo(1000 / 32768, 1e-5));
    });

    test('头里的 data 长度写大了，以实际字节为准，不越界', () {
      final Uint8List bytes = buildWav(<int>[100, 200]);
      ByteData.sublistView(bytes).setUint32(40, 999999, Endian.little);
      expect(() => Wav.decode(bytes), returnsNormally);
      expect(Wav.decode(bytes).samples, hasLength(2));
    });

    test('时长按采样数和采样率算', () {
      final WavAudio audio = Wav.decode(
        buildWav(List<int>.filled(16000, 0), sampleRate: 16000),
      );
      expect(audio.duration, const Duration(seconds: 1));
    });

    test('不是 WAV 的东西抛 WavFormatException，不是随便什么异常', () {
      // m4a 走到这里是常事——旧版本录的就是 m4a，得给出能看懂的提示
      expect(
        () => Wav.decode(Uint8List.fromList(List<int>.filled(64, 7))),
        throwsA(isA<WavFormatException>()),
      );
      expect(
        () => Wav.decode(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(isA<WavFormatException>()),
      );
    });

    test('有 RIFF 头但没有 data 块也要报错，不要给一段空音频冒充成功', () {
      final Uint8List head = Wav.header(
        sampleRate: 16000,
        channels: 1,
        bitsPerSample: 16,
        dataBytes: 0,
      );
      // 把 data 改名成 junk
      final Uint8List broken = Uint8List.fromList(head);
      broken.setRange(36, 40, 'junk'.codeUnits);
      expect(() => Wav.decode(broken), throwsA(isA<WavFormatException>()));
    });
  });

  group('重采样到 16 kHz', () {
    test('本来就是 16 k 就原样返回，不做无谓的计算', () {
      final Float32List input = Float32List.fromList(<double>[0.1, 0.2, 0.3]);
      expect(identical(Wav.resample(input, 16000), input), isTrue);
    });

    test('44.1 k 降到 16 k，长度按比例缩', () {
      final Float32List input = Float32List(44100);
      final Float32List out = Wav.resample(input, 44100);
      // 1 秒的音频，降完应该接近 16000 个点
      expect(out.length, closeTo(16000, 2));
    });

    test('降采样用窗口平均，不是直接抽点', () {
      // 32 k -> 16 k 就是两两取平均。直接抽点的话结果会是 [0, 2, 4]
      final Float32List input =
          Float32List.fromList(<double>[0, 1, 2, 3, 4, 5]);
      final Float32List out = Wav.resample(input, 32000);
      expect(out, hasLength(3));
      expect(out[0], closeTo(0.5, 1e-6));
      expect(out[1], closeTo(2.5, 1e-6));
      expect(out[2], closeTo(4.5, 1e-6));
    });

    test('窗口平均能压掉逐点跳变的高频，抽点压不掉', () {
      // 一串 +1/-1 交替，是最高频的信号。两两平均应该全变成 0；
      // 抽点的话会原样留下 +1，被当成一个低频信号——这就是混叠。
      final Float32List input = Float32List.fromList(
        List<double>.generate(64, (int i) => i.isEven ? 1.0 : -1.0),
      );
      final Float32List out = Wav.resample(input, 32000);
      for (final double v in out) {
        expect(v, closeTo(0, 1e-6));
      }
    });

    test('升采样走线性插值，端点不丢', () {
      final Float32List input = Float32List.fromList(<double>[0, 1]);
      final Float32List out = Wav.resample(input, 8000);
      expect(out.length, 4);
      expect(out[0], closeTo(0, 1e-6));
      expect(out[1], closeTo(0.5, 1e-6));
    });

    test('空数据和不合法的采样率都不崩', () {
      expect(Wav.resample(Float32List(0), 44100), isEmpty);
      final Float32List input = Float32List.fromList(<double>[1, 2]);
      expect(Wav.resample(input, 0), input);
      expect(Wav.resample(input, -1), input);
    });
  });

  test('从文件字节一步拿到能喂给模型的采样', () {
    final Uint8List bytes =
        buildWav(List<int>.filled(44100, 1000), sampleRate: 44100);
    final Float32List samples = Wav.samplesForModel(bytes);
    expect(samples.length, closeTo(16000, 2));
    expect(samples.first, closeTo(1000 / 32768, 1e-4));
  });
}
