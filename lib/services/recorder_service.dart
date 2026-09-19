import 'dart:io';

import 'package:record/record.dart';

import '../models/app_settings.dart';
import 'settings_controller.dart';

/// 录音：用系统麦克风录成 m4a(AAC) 文件，存在应用私有目录里。
class RecorderService {
  RecorderService._();

  static final RecorderService instance = RecorderService._();

  final AudioRecorder _recorder = AudioRecorder();

  Future<bool> hasPermission() => _recorder.hasPermission();

  Future<bool> get isRecording => _recorder.isRecording();

  /// 振幅流，用来驱动录音界面的实时波形。
  Stream<Amplitude> amplitude({
    Duration interval = const Duration(milliseconds: 120),
  }) =>
      _recorder.onAmplitudeChanged(interval);

  /// 码率与采样率取设置页选的音质档位。
  Future<void> start(String absolutePath) async {
    final AudioQuality quality = SettingsController.instance.value.audioQuality;
    await _recorder.start(
      RecordConfig(
        encoder: AudioEncoder.aacLc,
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
