import 'nav_app.dart';

/// 导航时的出行方式。各家地图的参数名不同，值在 NavigationLauncher 里映射。
enum TravelMode {
  driving('驾车'),
  walking('步行'),
  riding('骑行'),
  transit('公交');

  const TravelMode(this.label);

  final String label;
}

/// 地图底图样式，对应高德的 MapType。
enum MapKind {
  standard('标准'),
  satellite('卫星'),
  night('夜间');

  const MapKind(this.label);

  final String label;
}

/// 定位精度。越高越准也越费电，室内或只要个大概位置时可以调低。
enum LocateAccuracy {
  high('高精度', '室外定位最准，耗电最多'),
  balanced('均衡', '精度与耗电折中，日常够用'),
  powerSave('省电', '只用网络定位，精度约百米');

  const LocateAccuracy(this.label, this.hint);

  final String label;
  final String hint;
}

/// 列表默认排序。
enum MarkerSort {
  newestFirst('最近添加在前'),
  oldestFirst('最早添加在前'),
  nameAsc('按名称排列');

  const MarkerSort(this.label);

  final String label;
}

/// 录音音质。
///
/// 录出来的是 WAV（不压缩的 PCM），所以体积只由采样率决定，bitRate 只在
/// 机型不支持 WAV、回落到 AAC 时才起作用。之所以不压缩，是因为录完要把
/// 音频喂给本地的离线识别模型，模型吃的就是 PCM。
enum AudioQuality {
  saver('省空间', '16 kHz 单声道 · 约 1.9 MB/分钟', 64000, 16000),
  standard('标准', '22 kHz 单声道 · 约 2.6 MB/分钟', 96000, 22050),
  high('高音质', '44 kHz 单声道 · 约 5.3 MB/分钟', 128000, 44100);

  const AudioQuality(this.label, this.hint, this.bitRate, this.sampleRate);

  final String label;
  final String hint;
  final int bitRate;
  final int sampleRate;
}

/// 照片压缩程度。maxWidth 为 null 表示不缩放。
enum PhotoQuality {
  saver('省空间', '压到 70%，最宽 1280', 70, 1280),
  standard('标准', '压到 85%，最宽 2048', 85, 2048),
  original('原图', '不压缩，占空间较多', 100, null);

  const PhotoQuality(this.label, this.hint, this.quality, this.maxWidth);

  final String label;
  final String hint;
  final int quality;
  final double? maxWidth;
}

/// 定位超时可选的秒数。
const List<int> kLocateTimeoutChoices = <int>[10, 20, 30, 60];

/// 全部用户可配置项。不可变对象，改动走 copyWith 再整体落库。
class AppSettings {
  const AppSettings({
    this.defaultNavApp,
    this.travelMode = TravelMode.driving,
    this.mapKind = MapKind.standard,
    this.showTraffic = false,
    this.locateAccuracy = LocateAccuracy.high,
    this.locateTimeoutSeconds = 20,
    this.reverseGeocode = true,
    this.audioQuality = AudioQuality.standard,
    this.photoQuality = PhotoQuality.standard,
    this.markerSort = MarkerSort.newestFirst,
  });

  /// 默认导航应用。null 表示每次都弹面板让用户选。
  final NavApp? defaultNavApp;
  final TravelMode travelMode;
  final MapKind mapKind;
  final bool showTraffic;
  final LocateAccuracy locateAccuracy;
  final int locateTimeoutSeconds;

  /// 定位后是否顺带把经纬度解析成文字地址。
  final bool reverseGeocode;
  final AudioQuality audioQuality;
  final PhotoQuality photoQuality;
  final MarkerSort markerSort;

  Duration get locateTimeout => Duration(seconds: locateTimeoutSeconds);

  static const String keyDefaultNavApp = 'nav_default_app';
  static const String keyTravelMode = 'nav_travel_mode';
  static const String keyMapKind = 'map_kind';
  static const String keyShowTraffic = 'map_show_traffic';
  static const String keyLocateAccuracy = 'locate_accuracy';
  static const String keyLocateTimeout = 'locate_timeout_seconds';
  static const String keyReverseGeocode = 'locate_reverse_geocode';
  static const String keyAudioQuality = 'audio_quality';
  static const String keyPhotoQuality = 'photo_quality';
  static const String keyMarkerSort = 'list_sort';

  /// 「每次询问」在库里的存储值，与各 NavApp 的 name 不会重名。
  static const String navAskEveryTime = 'ask';

  AppSettings copyWith({
    NavApp? defaultNavApp,
    bool clearDefaultNavApp = false,
    TravelMode? travelMode,
    MapKind? mapKind,
    bool? showTraffic,
    LocateAccuracy? locateAccuracy,
    int? locateTimeoutSeconds,
    bool? reverseGeocode,
    AudioQuality? audioQuality,
    PhotoQuality? photoQuality,
    MarkerSort? markerSort,
  }) {
    return AppSettings(
      defaultNavApp:
          clearDefaultNavApp ? null : (defaultNavApp ?? this.defaultNavApp),
      travelMode: travelMode ?? this.travelMode,
      mapKind: mapKind ?? this.mapKind,
      showTraffic: showTraffic ?? this.showTraffic,
      locateAccuracy: locateAccuracy ?? this.locateAccuracy,
      locateTimeoutSeconds: locateTimeoutSeconds ?? this.locateTimeoutSeconds,
      reverseGeocode: reverseGeocode ?? this.reverseGeocode,
      audioQuality: audioQuality ?? this.audioQuality,
      photoQuality: photoQuality ?? this.photoQuality,
      markerSort: markerSort ?? this.markerSort,
    );
  }

  /// 摊平成键值对，交给 settings 表存。
  Map<String, String> toMap() {
    return <String, String>{
      keyDefaultNavApp: defaultNavApp?.name ?? navAskEveryTime,
      keyTravelMode: travelMode.name,
      keyMapKind: mapKind.name,
      keyShowTraffic: showTraffic ? 'true' : 'false',
      keyLocateAccuracy: locateAccuracy.name,
      keyLocateTimeout: '$locateTimeoutSeconds',
      keyReverseGeocode: reverseGeocode ? 'true' : 'false',
      keyAudioQuality: audioQuality.name,
      keyPhotoQuality: photoQuality.name,
      keyMarkerSort: markerSort.name,
    };
  }

  /// 从库里读出的键值对还原。任何缺失或无法识别的值都回落到默认值，
  /// 这样旧版本的库、手工改过的值都不会让 App 起不来。
  static AppSettings fromMap(Map<String, String> raw) {
    const AppSettings fallback = AppSettings();
    return AppSettings(
      defaultNavApp: _enumOrNull(NavApp.values, raw[keyDefaultNavApp]),
      travelMode: _enumOr(TravelMode.values, raw[keyTravelMode],
          fallback.travelMode),
      mapKind: _enumOr(MapKind.values, raw[keyMapKind], fallback.mapKind),
      showTraffic: _boolOr(raw[keyShowTraffic], fallback.showTraffic),
      locateAccuracy: _enumOr(LocateAccuracy.values, raw[keyLocateAccuracy],
          fallback.locateAccuracy),
      locateTimeoutSeconds:
          _timeoutOr(raw[keyLocateTimeout], fallback.locateTimeoutSeconds),
      reverseGeocode: _boolOr(raw[keyReverseGeocode], fallback.reverseGeocode),
      audioQuality: _enumOr(AudioQuality.values, raw[keyAudioQuality],
          fallback.audioQuality),
      photoQuality: _enumOr(PhotoQuality.values, raw[keyPhotoQuality],
          fallback.photoQuality),
      markerSort:
          _enumOr(MarkerSort.values, raw[keyMarkerSort], fallback.markerSort),
    );
  }

  static T _enumOr<T extends Enum>(List<T> values, String? name, T fallback) {
    return _enumOrNull(values, name) ?? fallback;
  }

  static T? _enumOrNull<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  static bool _boolOr(String? raw, bool fallback) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    return fallback;
  }

  /// 只接受预设的几档，避免存进奇怪的值导致定位一直等下去。
  static int _timeoutOr(String? raw, int fallback) {
    final int? parsed = raw == null ? null : int.tryParse(raw);
    if (parsed == null || !kLocateTimeoutChoices.contains(parsed)) {
      return fallback;
    }
    return parsed;
  }
}
