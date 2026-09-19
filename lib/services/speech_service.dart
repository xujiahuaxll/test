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

  /// 连续起不来的次数。成功一次就清零。
  int _restartAttempts = 0;

  /// 连着这么多次都起不来才真的放弃，避免无限重试。
  static const int _maxRestartAttempts = 6;
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
          // 识别引擎报错未必是致命的（常见的是一段结束时的 no match /
          // speech timeout），照样续听，由 _scheduleRestart 的次数上限兜底。
          _scheduleRestart();
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
    _restartAttempts = 0;
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
      // 起来了，之前的失败不再计数
      _restartAttempts = 0;
    } catch (_) {
      // 一次起不来不代表以后都不行：上一段刚结束时引擎常常还在收尾。
      // 这里原本直接把 _wantListening 置否，等于让后面所有续听都不再发生，
      // 表现就是「说一句停几秒，只转了第一段，后面全没了」。
      _scheduleRestart();
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
      _scheduleRestart();
    }
  }

  /// 退避重试地把识别续上。
  ///
  /// 退避是必要的：刚结束的那一瞬间引擎多半还没释放，立刻重试必然失败。
  /// 次数上限也是必要的：真的坏了就别无限空转。
  void _scheduleRestart() {
    if (!_wantListening) return;
    if (shouldGiveUp(_restartAttempts)) {
      _wantListening = false;
      return;
    }
    final int attempt = _restartAttempts++;
    Future<void>.delayed(restartDelayFor(attempt), () {
      if (!_wantListening || _speech.isListening) return;
      _listen();
    });
  }

  /// 第 [attempt] 次重试等多久。指数退避，4 次之后封顶在 1.6 秒。
  ///
  /// 不能立刻重试：一段识别刚结束时引擎还在收尾，这会儿去 listen 必然
  /// 抛错，抛一次就少一次重试机会，反而把能续上的也耗没了。
  static Duration restartDelayFor(int attempt) {
    final int capped = attempt < 0 ? 0 : (attempt > 3 ? 3 : attempt);
    return Duration(milliseconds: 200 * (1 << capped));
  }

  /// 连着这么多次都起不来就别再空转了。
  static bool shouldGiveUp(int attempts) => attempts >= _maxRestartAttempts;

  /// 已经连着失败多少次没起来。界面可以据此提示用户。
  int get restartAttempts => _restartAttempts;

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
