import 'dart:async';
import 'dart:io';
import 'dart:isolate';


import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../utils/wav.dart';

/// 离线语音转文字。
///
/// 走 sherpa-onnx + 一个 78 MB 的中文 Paraformer 小模型，模型随 APK 一起
/// 发，识别全程不联网，也不需要系统的语音识别服务。
///
/// 为什么不用系统的 SpeechRecognizer：它只认实时麦克风输入，没法识别已经
/// 录好的文件，于是必须和录音抢麦克风——两边都要独占，同时开必然有一个起
/// 不来。表现就是「只转了第一段，后面全没了」。换成本地模型之后，录音正常
/// 走它的，录完再把音频喂给模型，两件事不再冲突。
///
/// 代价：识别是录完之后跑的，不是边录边出字。实时要流式模型，最小的也有
/// 437 MB，装进 APK 不现实。
class AsrService {
  AsrService._();

  static final AsrService instance = AsrService._();

  /// 模型文件在 assets 里的位置。由 scripts/fetch-asr-model.sh 放进去，
  /// 不进 git（78 MB 的二进制没必要让每次 clone 都拖一份）。
  static const String modelAsset = 'assets/asr/model.int8.onnx';
  static const String tokensAsset = 'assets/asr/tokens.txt';

  _AsrWorker? _worker;
  Future<AsrModel?>? _modelFuture;

  /// 覆盖模型落地目录，仅用于测试。
  Directory? _stageDirOverride;

  /// sherpa 原生库所在目录，仅用于测试。
  ///
  /// 线上不需要：APK 里的 .so 就在系统的加载路径上，
  /// `DynamicLibrary.open('libsherpa-onnx-c-api.so')` 直接能找到。
  /// 但 flutter_tester 跑的是桌面进程，.so 还躺在 pub-cache 里，
  /// 得告诉它去哪找。
  String? _nativeDirOverride;

  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void overrideStageDirForTesting(Directory dir) => _stageDirOverride = dir;

  @visibleForTesting
  // ignore: use_setters_to_change_properties
  void overrideNativeDirForTesting(String dir) => _nativeDirOverride = dir;

  /// 本机能不能做离线识别。模型没打进包里就是不能。
  Future<bool> isAvailable() async => await _ensureModel() != null;

  /// 识别一个音频文件，返回识别出的文字。
  ///
  /// 失败一律抛 [AsrFailure]，调用方接住了给个「重试」就行——录音本身
  /// 已经存好了，转写失败不该连累它。
  Future<String> transcribeFile(String absolutePath) async {
    final File file = File(absolutePath);
    if (!await file.exists()) {
      throw const AsrFailure('找不到录音文件');
    }

    final Float32List samples;
    try {
      samples = Wav.samplesForModel(await file.readAsBytes());
    } on WavFormatException catch (e) {
      // 旧版本录的是 m4a，解不开是意料之中的，说清楚别让人以为是坏了。
      throw AsrFailure('这段录音不是可识别的格式：${e.message}');
    } catch (e) {
      throw AsrFailure('读取录音失败：$e');
    }

    if (samples.isEmpty) throw const AsrFailure('这段录音是空的');
    return transcribeSamples(samples);
  }

  /// 识别一段已经解好的 16 kHz 单声道采样。
  Future<String> transcribeSamples(Float32List samples) async {
    final AsrModel? model = await _ensureModel();
    if (model == null) {
      throw const AsrFailure('这个版本没有带语音模型，无法转文字');
    }
    final _AsrWorker worker =
        _worker ??= await _AsrWorker.spawn(model, _nativeDirOverride);
    return worker.run(samples);
  }

  /// 放掉识别用的 isolate 和它占的内存（模型加载进去有几百兆）。
  Future<void> release() async {
    final _AsrWorker? worker = _worker;
    _worker = null;
    await worker?.dispose();
  }

  /// 把模型从 assets 复制到应用目录。
  ///
  /// ONNX Runtime 要的是文件路径，读不了 Flutter 的 assets（那是打包在
  /// APK 里的压缩条目，没有独立的文件系统路径）。所以必须先落地一份。
  /// 代价是磁盘上有两份，加起来约 156 MB。
  Future<AsrModel?> _ensureModel() {
    return _modelFuture ??= _stageModel().catchError((Object _) => null);
  }

  Future<AsrModel?> _stageModel() async {
    final Directory dir = _stageDirOverride ??
        Directory(p.join((await getApplicationSupportDirectory()).path, 'asr'));
    if (!await dir.exists()) await dir.create(recursive: true);

    final String? model = await _stageOne(dir, modelAsset);
    final String? tokens = await _stageOne(dir, tokensAsset);
    if (model == null || tokens == null) return null;
    return AsrModel(modelPath: model, tokensPath: tokens);
  }

  /// 复制单个文件，返回落地后的绝对路径；assets 里没有则返回 null。
  Future<String?> _stageOne(Directory dir, String asset) async {
    final ByteData data;
    try {
      data = await rootBundle.load(asset);
    } catch (_) {
      // 没跑过 scripts/fetch-asr-model.sh 的构建就是这个下场
      return null;
    }
    final File out = File(p.join(dir.path, p.basename(asset)));
    if (!shouldRestage(
      existingLength: await out.exists() ? await out.length() : null,
      assetLength: data.lengthInBytes,
    )) {
      return out.path;
    }
    await out.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return out.path;
  }

  /// 要不要重新复制一遍。
  ///
  /// 只比长度，不算哈希：模型 78 MB，每次启动都哈希一遍要好几秒，
  /// 而这里真正要挡住的两种情况——「还没复制过」和「上次复制到一半被杀掉」
  /// ——长度都对不上。换模型时长度也必然变。
  static bool shouldRestage({
    required int? existingLength,
    required int assetLength,
  }) =>
      existingLength == null || existingLength != assetLength;
}

/// 落地之后的模型文件位置。
class AsrModel {
  const AsrModel({required this.modelPath, required this.tokensPath});

  final String modelPath;
  final String tokensPath;
}

/// 识别失败。消息是给用户看的。
class AsrFailure implements Exception {
  const AsrFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 常驻的识别 isolate。
///
/// 常驻是为了把模型只加载一次：建 OfflineRecognizer 要读那 78 MB，
/// 每次识别都重来一遍的话，点一下「重试」要干等好几秒。
/// 放在 isolate 里则是因为识别本身是纯 CPU 的同步活，跑在主 isolate 上
/// 界面会整个卡住。
class _AsrWorker {
  _AsrWorker._(this._isolate, this._toWorker, this._fromWorker, Stream<dynamic> replies) {
    _subscription = replies.listen(_handle);
  }

  final Isolate _isolate;
  final SendPort _toWorker;
  final ReceivePort _fromWorker;
  late final StreamSubscription<dynamic> _subscription;

  final Map<int, Completer<String>> _pending = <int, Completer<String>>{};
  int _nextId = 0;

  static Future<_AsrWorker> spawn(AsrModel model, String? nativeDir) async {
    final ReceivePort fromWorker = ReceivePort();
    // 先转成广播流：下面要先 await 第一条（worker 的 SendPort），
    // 之后还要继续收识别结果，单订阅流做不到。
    final Stream<dynamic> replies = fromWorker.asBroadcastStream();
    final Isolate isolate = await Isolate.spawn(
      _asrWorkerMain,
      _AsrBoot(
        fromWorker.sendPort,
        model.modelPath,
        model.tokensPath,
        nativeDir,
      ),
      debugName: 'asr',
    );
    final SendPort toWorker = await replies.first as SendPort;
    return _AsrWorker._(isolate, toWorker, fromWorker, replies);
  }

  Future<String> run(Float32List samples) {
    final int id = _nextId++;
    final Completer<String> completer = Completer<String>();
    _pending[id] = completer;
    _toWorker.send(_AsrJob(id, samples));
    return completer.future;
  }

  void _handle(dynamic message) {
    if (message is! _AsrReply) return;
    final Completer<String>? completer = _pending.remove(message.id);
    if (completer == null || completer.isCompleted) return;
    final String? error = message.error;
    if (error != null) {
      completer.completeError(AsrFailure(error));
    } else {
      completer.complete(message.text);
    }
  }

  Future<void> dispose() async {
    for (final Completer<String> c in _pending.values) {
      if (!c.isCompleted) c.completeError(const AsrFailure('识别已取消'));
    }
    _pending.clear();
    await _subscription.cancel();
    _fromWorker.close();
    _isolate.kill(priority: Isolate.immediate);
  }
}

class _AsrBoot {
  const _AsrBoot(this.reply, this.modelPath, this.tokensPath, this.nativeDir);

  final SendPort reply;
  final String modelPath;
  final String tokensPath;

  /// 原生库所在目录。线上为 null，走系统默认的查找路径。
  final String? nativeDir;
}

class _AsrJob {
  const _AsrJob(this.id, this.samples);

  final int id;
  final Float32List samples;
}

class _AsrReply {
  const _AsrReply(this.id, {this.text = '', this.error});

  final int id;
  final String text;
  final String? error;
}

/// isolate 入口。必须是顶层函数。
void _asrWorkerMain(_AsrBoot boot) {
  final ReceivePort inbox = ReceivePort();
  boot.reply.send(inbox.sendPort);

  sherpa.OfflineRecognizer? recognizer;

  inbox.listen((dynamic message) {
    if (message is! _AsrJob) return;
    try {
      recognizer ??=
          _createRecognizer(boot.modelPath, boot.tokensPath, boot.nativeDir);
      final sherpa.OfflineStream stream = recognizer!.createStream();
      try {
        stream.acceptWaveform(
          samples: message.samples,
          sampleRate: Wav.modelSampleRate,
        );
        recognizer!.decode(stream);
        final String text = recognizer!.getResult(stream).text.trim();
        boot.reply.send(_AsrReply(message.id, text: text));
      } finally {
        stream.free();
      }
    } catch (e) {
      boot.reply.send(_AsrReply(message.id, error: '识别失败：$e'));
    }
  });
}

sherpa.OfflineRecognizer _createRecognizer(
  String modelPath,
  String tokensPath,
  String? nativeDir,
) {
  // 每个 isolate 都要自己 initBindings，主 isolate 调过不算数。
  sherpa.initBindings(nativeDir);
  return sherpa.OfflineRecognizer(
    sherpa.OfflineRecognizerConfig(
      model: sherpa.OfflineModelConfig(
        paraformer: sherpa.OfflineParaformerModelConfig(model: modelPath),
        tokens: tokensPath,
        // 手机上给 2 条线程：再多收益很小，还会把前台界面挤卡。
        numThreads: 2,
        modelType: 'paraformer',
        debug: false,
      ),
    ),
  );
}
