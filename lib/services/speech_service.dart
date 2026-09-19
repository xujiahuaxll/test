import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'settings_controller.dart';

/// 语音转文字：走系统自带的识别能力
/// （iOS SFSpeechRecognizer / Android SpeechRecognizer），不接第三方云服务。
///
/// 系统一次 listen 会在静音后自动结束，这里在录音未停止前自动续听，
/// 并把每段最终结果拼接起来，得到一整段连续的转写文字。
class SpeechService {
  SpeechService._();

  static final SpeechService instance = SpeechService._();

  final SpeechToText _speech = SpeechToText();

  bool _initialized = false;
  bool _available = false;
  bool _wantListening = false;
  String _committed = '';
  ValueChanged<String>? _onText;

  bool get available => _available;

  bool get isListening => _speech.isListening;

  /// 初始化一次即可；设备不支持或用户拒绝权限时返回 false，
  /// 调用方据此降级为「只录音、不转写」。
  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    _initialized = true;
    try {
      _available = await _speech.initialize(
        onStatus: _handleStatus,
        onError: (dynamic error) {
          if (_wantListening) _restart();
        },
      );
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// 开始识别。onText 会收到「已确认段落 + 当前实时片段」的完整文本。
  Future<bool> start({
    required ValueChanged<String> onText,
    String initial = '',
  }) async {
    if (!await ensureInitialized()) return false;
    _onText = onText;
    _committed = initial;
    _wantListening = true;
    await _listen();
    return true;
  }

  Future<void> _listen() async {
    if (!_wantListening) return;
    try {
      await _speech.listen(
        onResult: _handleResult,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: false,
          listenMode: ListenMode.dictation,
          localeId: SettingsController.instance.value.speechLocale.id,
          listenFor: const Duration(minutes: 5),
          pauseFor: const Duration(seconds: 15),
        ),
      );
    } catch (_) {
      _wantListening = false;
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    final String text = result.recognizedWords;
    if (result.finalResult) {
      if (text.isNotEmpty) {
        _committed = _committed.isEmpty ? text : '$_committed$text';
      }
      _onText?.call(_committed);
    } else {
      _onText?.call('$_committed$text');
    }
  }

  void _handleStatus(String status) {
    // 系统在静音后会结束当前 session，这里自动续上，保证长时间录音不断流。
    if (status == 'done' || status == 'notListening') {
      if (_wantListening) _restart();
    }
  }

  void _restart() {
    Future<void>.delayed(const Duration(milliseconds: 200), () {
      if (_wantListening && !_speech.isListening) _listen();
    });
  }

  /// 停止识别，返回最终整段文字。
  Future<String> stop() async {
    _wantListening = false;
    try {
      await _speech.stop();
    } catch (_) {
      // 未在识别时 stop 会抛错，忽略。
    }
    _onText = null;
    return _committed;
  }

  Future<void> cancel() async {
    _wantListening = false;
    try {
      await _speech.cancel();
    } catch (_) {}
    _committed = '';
    _onText = null;
  }
}
