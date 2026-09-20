import 'dart:io';

import 'package:record/record.dart';

import '../models/app_settings.dart';
import 'settings_controller.dart';

/// 录音：用系统麦克风录成 WAV 文件，存在应用私有目录里。
///
/// 为什么是 WAV 不是 m4a：录完要把音频喂给本地的离线识别模型，模型吃的是
/// PCM 采样，AAC 得先解码。WAV 就是带头的裸 PCM，读出来直接能用，省掉一层
/// 解码，也少一处可能失败的地方。代价是文件大，不过语音备注都很短。
///
/// 机型不支持 WAV 时回落到 m4a（AAC）——录音本身必须保住，转文字没了
/// 还能手打。
class RecorderService {
  RecorderService._();

  static final RecorderService instance = RecorderService._();

  final AudioRecorder _recorder = AudioRecorder();

  RecordFormat? _format;

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  /// 振幅流，用来驱动录音界面的实时波形。
  Stream<Amplitude> amplitude({
    Duration interval = const Duration(milliseconds: 120),
  }) =>
      _recorder.onAmplitudeChanged(interval);

  /// 这台机器该用哪种格式录。
  ///
  /// 要先问再分配文件名——路径的扩展名得和真实格式对上，
  /// 不然播放器和识别模型都会被后缀误导。
  Future<RecordFormat> preferredFormat() async {
    final RecordFormat? cached = _format;
    if (cached != null) return cached;
    bool wav = false;
    try {
      wav = await _recorder.isEncoderSupported(AudioEncoder.wav);
    } catch (_) {
      // 查询本身失败就当不支持，回落到一定能录的 AAC。
      wav = false;
    }
    return _format = wav ? RecordFormat.wav : RecordFormat.m4a;
  }

  /// 开始录音。[absolutePath] 的扩展名要和 [format] 对上。
  Future<void> start(String absolutePath, RecordFormat format) async {
    final AudioQuality quality = SettingsController.instance.value.audioQuality;
    await _recorder.start(
      RecordConfig(
        encoder: format == RecordFormat.wav
            ? AudioEncoder.wav
            : AudioEncoder.aacLc,
        // WAV 不压缩，bitRate 传了也没用，采样率才是决定体积的那个。
        bitRate: quality.bitRate,
        sampleRate: quality.sampleRate,
        numChannels: 1,
      ),
      path: absolutePath,
    );
  }

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  /// 结束录音，返回落盘文件路径（失败时为 null）。
  Future<String?> stop() => _recorder.stop();

  /// 放弃这次录音并删掉已产生的文件。
  Future<void> cancel(String absolutePath) async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // 未在录音时 cancel 会抛错，忽略即可。
    }
    final File file = File(absolutePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<void> dispose() => _recorder.dispose();
}

/// 一次录音落盘用的格式。
enum RecordFormat {
  /// 带头的裸 PCM，能直接交给离线识别模型。
  wav('.wav', true),

  /// AAC。体积小，但本地模型解不开，只能录不能转。
  m4a('.m4a', false);

  const RecordFormat(this.extension, this.transcribable);

  final String extension;

  /// 这个格式能不能拿去做离线转写。
  final bool transcribable;
}
