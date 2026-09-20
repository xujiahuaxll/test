import 'dart:typed_data';

/// 一段解出来的 PCM 音频。
class WavAudio {
  const WavAudio({
    required this.sampleRate,
    required this.channels,
    required this.samples,
  });

  final int sampleRate;
  final int channels;

  /// 混成单声道、归一化到 -1~1 的采样点。
  final Float32List samples;

  Duration get duration => sampleRate <= 0
      ? Duration.zero
      : Duration(
          microseconds: (samples.length * 1000000 / sampleRate).round(),
        );
}

/// WAV 文件读不出来时抛这个，调用方据此降级为「只录音、没有文字」。
class WavFormatException implements Exception {
  const WavFormatException(this.message);

  final String message;

  @override
  String toString() => 'WavFormatException: $message';
}

/// RIFF/WAVE 的最小解析与重采样。
///
/// 为什么要自己解：离线识别模型吃的是 16 kHz 单声道的浮点采样，
/// 而录音文件按用户选的音质档位落盘（可能是 22 k 或 44.1 k）。
/// 中间这一步转换放在纯 Dart 里，不依赖设备也不依赖原生库，能单测。
class Wav {
  const Wav._();

  /// 模型要求的采样率。paraformer 的声学特征就是按 16 k 算的，
  /// 喂别的采样率进去不会报错，只会识别得一塌糊涂。
  static const int modelSampleRate = 16000;

  /// 解析一个 WAV 文件的字节。
  ///
  /// 只认 PCM（16/8/32 位整数与 32 位浮点）。多声道会混成单声道——
  /// 识别只需要一路，混掉反而比丢掉一路更稳。
  static WavAudio decode(Uint8List bytes) {
    if (bytes.length < 12) {
      throw const WavFormatException('文件太短，不是 WAV');
    }
    final ByteData data = ByteData.sublistView(bytes);
    if (_tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
      throw const WavFormatException('不是 RIFF/WAVE 文件');
    }

    int format = 1;
    int channels = 1;
    int sampleRate = 0;
    int bitsPerSample = 16;
    int? dataStart;
    int dataLength = 0;

    // 逐块走。真实文件里 fmt 和 data 之间常常夹着 LIST / fact 之类的块，
    // 直接按固定偏移 44 取数据的写法碰上就废了。
    int offset = 12;
    while (offset + 8 <= bytes.length) {
      final String id = _tag(bytes, offset);
      final int size = data.getUint32(offset + 4, Endian.little);
      final int body = offset + 8;
      if (id == 'fmt ' && body + 16 <= bytes.length) {
        format = data.getUint16(body, Endian.little);
        channels = data.getUint16(body + 2, Endian.little);
        sampleRate = data.getUint32(body + 4, Endian.little);
        bitsPerSample = data.getUint16(body + 14, Endian.little);
      } else if (id == 'data') {
        dataStart = body;
        // 有些录音器边录边写，头里的长度还是 0 或者过大，以实际字节为准。
        final int available = bytes.length - body;
        dataLength = size == 0 || size > available ? available : size;
      }
      // 块是按偶数字节对齐的，奇数长度后面补一个填充字节。
      offset = body + size + (size.isOdd ? 1 : 0);
    }

    if (dataStart == null) throw const WavFormatException('没有找到 data 块');
    if (channels <= 0) throw const WavFormatException('声道数不合法');
    if (sampleRate <= 0) throw const WavFormatException('采样率不合法');

    final Float32List mono = _toMono(
      data,
      start: dataStart,
      length: dataLength,
      channels: channels,
      bitsPerSample: bitsPerSample,
      isFloat: format == 3,
    );
    return WavAudio(
      sampleRate: sampleRate,
      channels: channels,
      samples: mono,
    );
  }

  /// 拼一个 44 字节的 WAV 头。
  ///
  /// 只在需要把裸 PCM 存成能播的文件时用得上。
  static Uint8List header({
    required int sampleRate,
    required int channels,
    required int bitsPerSample,
    required int dataBytes,
  }) {
    final Uint8List head = Uint8List(44);
    final ByteData out = ByteData.sublistView(head);
    final int blockAlign = channels * bitsPerSample ~/ 8;

    _writeTag(head, 0, 'RIFF');
    out.setUint32(4, 36 + dataBytes, Endian.little);
    _writeTag(head, 8, 'WAVE');
    _writeTag(head, 12, 'fmt ');
    out.setUint32(16, 16, Endian.little);
    out.setUint16(20, 1, Endian.little); // PCM
    out.setUint16(22, channels, Endian.little);
    out.setUint32(24, sampleRate, Endian.little);
    out.setUint32(28, sampleRate * blockAlign, Endian.little);
    out.setUint16(32, blockAlign, Endian.little);
    out.setUint16(34, bitsPerSample, Endian.little);
    _writeTag(head, 36, 'data');
    out.setUint32(40, dataBytes, Endian.little);
    return head;
  }

  /// 重采样到 [modelSampleRate]。
  ///
  /// 降采样走「窗口取平均」而不是直接抽点：抽点会把高频折回来变成噪声
  /// （混叠），识别率掉得很明显；取平均本身就是一道粗糙的低通。
  /// 升采样走线性插值——反正信息已经没了，插得再花也补不回来。
  static Float32List resample(Float32List input, int fromRate) {
    if (fromRate == modelSampleRate || input.isEmpty) return input;
    if (fromRate <= 0) return input;

    if (fromRate > modelSampleRate) {
      final double ratio = fromRate / modelSampleRate;
      final int outLength = (input.length / ratio).floor();
      final Float32List out = Float32List(outLength);
      for (int i = 0; i < outLength; i++) {
        final int start = (i * ratio).floor();
        int end = ((i + 1) * ratio).floor();
        if (end <= start) end = start + 1;
        if (end > input.length) end = input.length;
        double sum = 0;
        for (int j = start; j < end; j++) {
          sum += input[j];
        }
        out[i] = sum / (end - start);
      }
      return out;
    }

    final double ratio = fromRate / modelSampleRate;
    final int outLength = (input.length / ratio).floor();
    final Float32List out = Float32List(outLength);
    for (int i = 0; i < outLength; i++) {
      final double pos = i * ratio;
      final int left = pos.floor();
      final int right = left + 1 < input.length ? left + 1 : left;
      final double t = pos - left;
      out[i] = input[left] * (1 - t) + input[right] * t;
    }
    return out;
  }

  /// 解析 + 重采样一步到位，拿到能直接喂给模型的采样点。
  static Float32List samplesForModel(Uint8List bytes) {
    final WavAudio audio = decode(bytes);
    return resample(audio.samples, audio.sampleRate);
  }

  static Float32List _toMono(
    ByteData data, {
    required int start,
    required int length,
    required int channels,
    required int bitsPerSample,
    required bool isFloat,
  }) {
    final int bytesPerSample = bitsPerSample ~/ 8;
    if (bytesPerSample <= 0) {
      throw const WavFormatException('位深不合法');
    }
    final int frameBytes = bytesPerSample * channels;
    final int frames = length ~/ frameBytes;
    final Float32List out = Float32List(frames);

    for (int frame = 0; frame < frames; frame++) {
      double sum = 0;
      for (int ch = 0; ch < channels; ch++) {
        final int at = start + frame * frameBytes + ch * bytesPerSample;
        sum += _readSample(data, at, bitsPerSample, isFloat);
      }
      out[frame] = sum / channels;
    }
    return out;
  }

  static double _readSample(
    ByteData data,
    int at,
    int bitsPerSample,
    bool isFloat,
  ) {
    if (isFloat && bitsPerSample == 32) {
      return data.getFloat32(at, Endian.little);
    }
    switch (bitsPerSample) {
      case 8:
        // 8 位 WAV 是无符号的，128 是静音
        return (data.getUint8(at) - 128) / 128.0;
      case 16:
        return data.getInt16(at, Endian.little) / 32768.0;
      case 24:
        final int b0 = data.getUint8(at);
        final int b1 = data.getUint8(at + 1);
        final int b2 = data.getUint8(at + 2);
        int value = b0 | (b1 << 8) | (b2 << 16);
        if (value & 0x800000 != 0) value -= 0x1000000;
        return value / 8388608.0;
      case 32:
        return data.getInt32(at, Endian.little) / 2147483648.0;
      default:
        throw WavFormatException('不支持 $bitsPerSample 位的采样');
    }
  }

  static String _tag(Uint8List bytes, int at) {
    if (at + 4 > bytes.length) return '';
    return String.fromCharCodes(bytes, at, at + 4);
  }

  static void _writeTag(Uint8List bytes, int at, String tag) {
    for (int i = 0; i < 4; i++) {
      bytes[at + i] = tag.codeUnitAt(i);
    }
  }
}
