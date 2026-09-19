import 'package:flutter_test/flutter_test.dart';
import 'package:location_marker/services/speech_service.dart';

void main() {
  group('录音转文字的续听退避', () {
    test('第一次几乎立刻重试，之后逐次翻倍', () {
      expect(SpeechService.restartDelayFor(0), const Duration(milliseconds: 200));
      expect(SpeechService.restartDelayFor(1), const Duration(milliseconds: 400));
      expect(SpeechService.restartDelayFor(2), const Duration(milliseconds: 800));
    });

    test('退避封顶，不会越等越久到用户以为坏了', () {
      expect(
        SpeechService.restartDelayFor(3),
        const Duration(milliseconds: 1600),
      );
      expect(
        SpeechService.restartDelayFor(50),
        SpeechService.restartDelayFor(3),
      );
    });

    test('异常的次数也给得出一个合法的等待时间', () {
      expect(SpeechService.restartDelayFor(-1), SpeechService.restartDelayFor(0));
    });
  });

  group('什么时候才算真的起不来', () {
    test('偶尔起不来要接着试：说一句停两三秒再说，后面那几段全靠它续上', () {
      // 这里原本是「抛一次就永久放弃」，表现就是只转了第一段
      expect(SpeechService.shouldGiveUp(0), isFalse);
      expect(SpeechService.shouldGiveUp(1), isFalse);
      expect(SpeechService.shouldGiveUp(5), isFalse);
    });

    test('连着试太多次还是不行就收手，别无限空转', () {
      expect(SpeechService.shouldGiveUp(6), isTrue);
      expect(SpeechService.shouldGiveUp(100), isTrue);
    });
  });
}
