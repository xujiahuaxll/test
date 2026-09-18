import 'package:flutter/material.dart';

/// Demo 用的照片占位：没有真实图片资源，用渐变 + 图标模拟一张照片。
class DemoPhoto {
  const DemoPhoto(this.colors, this.icon, this.label);

  final List<Color> colors;
  final IconData icon;
  final String label;

  LinearGradient get gradient => LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

/// 语音备注（Demo 数据：只有时长和转写文字，不涉及真实音频）。
class VoiceNote {
  const VoiceNote({
    required this.duration,
    required this.transcript,
  });

  final Duration duration;
  final String transcript;

  String get durationText {
    final String m = duration.inMinutes.toString().padLeft(2, '0');
    final String s = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 一条地点标记。
class LocationMark {
  const LocationMark({
    required this.id,
    required this.name,
    required this.tags,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.photos = const <DemoPhoto>[],
    this.note = '',
    this.voiceNote,
  });

  final String id;
  final String name;
  final List<String> tags;
  final String address;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  final List<DemoPhoto> photos;
  final String note;
  final VoiceNote? voiceNote;

  bool get hasVoice => voiceNote != null;

  String get coordinateText =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  /// 列表里展示的相对时间，Demo 里按固定「今天」计算。
  String relativeTime(DateTime now) {
    final Duration diff = now.difference(createdAt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${createdAt.month}月${createdAt.day}日';
  }
}
