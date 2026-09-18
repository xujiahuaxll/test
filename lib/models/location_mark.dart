import 'package:flutter/foundation.dart';

/// 一条地点标记。照片与录音在库里只存**相对路径**
/// （iOS 沙盒目录在版本更新后会变，绝对路径会失效）。
@immutable
class LocationMark {
  const LocationMark({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const <String>[],
    this.address,
    this.accuracy,
    this.photoPaths = const <String>[],
    this.note = '',
    this.audioPath,
    this.audioDuration,
    this.transcript,
    this.waveform = const <double>[],
  });

  final String id;
  final String name;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;

  /// 逆地理编码得到的地址，拿不到时为 null，界面回落显示经纬度。
  final String? address;
  final double? accuracy;
  final List<String> photoPaths;
  final String note;
  final String? audioPath;
  final Duration? audioDuration;
  final String? transcript;

  /// 录音时采集的振幅包络（0~1），播放条用它画真实波形。
  final List<double> waveform;

  bool get hasVoice => audioPath != null;

  String get coordinateText =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  String get addressOrCoordinate => address?.isNotEmpty == true
      ? address!
      : '未获取到地址 · $coordinateText';

  String get durationText => formatDuration(audioDuration ?? Duration.zero);

  static List<double> parseWaveform(String? raw) {
    if (raw == null || raw.isEmpty) return const <double>[];
    return raw
        .split(',')
        .map((String v) => double.tryParse(v) ?? 0)
        .where((double v) => v > 0)
        .toList();
  }

  static String formatDuration(Duration d) {
    final String m = d.inMinutes.toString().padLeft(2, '0');
    final String s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String relativeTime([DateTime? now]) {
    final DateTime ref = now ?? DateTime.now();
    final Duration diff = ref.difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${createdAt.month}月${createdAt.day}日';
  }

  LocationMark copyWith({
    String? name,
    List<String>? tags,
    String? address,
    double? latitude,
    double? longitude,
    double? accuracy,
    List<String>? photoPaths,
    String? note,
    Object? audioPath = _unset,
    Object? audioDuration = _unset,
    Object? transcript = _unset,
    List<double>? waveform,
    DateTime? updatedAt,
  }) {
    return LocationMark(
      id: id,
      name: name ?? this.name,
      tags: tags ?? this.tags,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: accuracy ?? this.accuracy,
      photoPaths: photoPaths ?? this.photoPaths,
      note: note ?? this.note,
      audioPath:
          audioPath == _unset ? this.audioPath : audioPath as String?,
      audioDuration: audioDuration == _unset
          ? this.audioDuration
          : audioDuration as Duration?,
      transcript:
          transcript == _unset ? this.transcript : transcript as String?,
      waveform: waveform ?? this.waveform,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toRow() => <String, Object?>{
        'id': id,
        'name': name,
        'note': note,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'audio_path': audioPath,
        'audio_duration_ms': audioDuration?.inMilliseconds,
        'transcript': transcript,
        'waveform': waveform.isEmpty
            ? null
            : waveform.map((double v) => v.toStringAsFixed(2)).join(','),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  static LocationMark fromRow(
    Map<String, Object?> row, {
    List<String> tags = const <String>[],
    List<String> photoPaths = const <String>[],
  }) {
    final int? durationMs = row['audio_duration_ms'] as int?;
    return LocationMark(
      id: row['id']! as String,
      name: row['name']! as String,
      note: (row['note'] as String?) ?? '',
      address: row['address'] as String?,
      latitude: (row['latitude']! as num).toDouble(),
      longitude: (row['longitude']! as num).toDouble(),
      accuracy: (row['accuracy'] as num?)?.toDouble(),
      audioPath: row['audio_path'] as String?,
      audioDuration:
          durationMs == null ? null : Duration(milliseconds: durationMs),
      transcript: row['transcript'] as String?,
      waveform: parseWaveform(row['waveform'] as String?),
      createdAt:
          DateTime.fromMillisecondsSinceEpoch(row['created_at']! as int),
      updatedAt:
          DateTime.fromMillisecondsSinceEpoch(row['updated_at']! as int),
      tags: tags,
      photoPaths: photoPaths,
    );
  }
}

const Object _unset = Object();
