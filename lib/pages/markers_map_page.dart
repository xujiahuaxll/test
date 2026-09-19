import 'dart:math';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../config/amap_config.dart';
import '../data/marker_repository.dart';
import '../models/app_settings.dart';
import '../models/location_mark.dart';
import '../services/amap_runtime.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/coordinate.dart';
import '../widgets/common.dart';
import '../widgets/nav_app_sheet.dart';
import 'marker_detail_page.dart';

/// 全局地图：一张地图上显示所有标记，点标记从底部抽屉看详情。
class MarkersMapPage extends StatefulWidget {
  const MarkersMapPage({super.key});

  @override
  State<MarkersMapPage> createState() => MarkersMapPageState();
}

class MarkersMapPageState extends State<MarkersMapPage> {
  final MarkerRepository _repo = MarkerRepository.instance;

  List<LocationMark> _marks = <LocationMark>[];
  bool _loading = true;

  /// 地图 Marker 的 id -> 标记，点击回调只带回 id。
  final Map<String, LocationMark> _markerIndex = <String, LocationMark>{};
  Set<Marker> _markers = <Marker>{};

  LocationMark? _selected;
  AMapController? _controller;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final List<LocationMark> marks = await _repo.query(
      sort: SettingsController.instance.value.markerSort,
    );
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _markers = _buildMarkers(marks);
      _loading = false;
      // 刷新后原选中项可能已被删除
      if (_selected != null &&
          !marks.any((LocationMark m) => m.id == _selected!.id)) {
        _selected = null;
      }
    });
  }

  Set<Marker> _buildMarkers(List<LocationMark> marks) {
    _markerIndex.clear();
    final Set<Marker> result = <Marker>{};
    for (final LocationMark mark in marks) {
      final LatLngPair gcj =
          CoordinateConverter.wgs84ToGcj02(mark.latitude, mark.longitude);
      final Marker marker = Marker(
        position: LatLng(gcj.latitude, gcj.longitude),
        infoWindowEnable: false,
        onTap: _onMarkerTap,
      );
      _markerIndex[marker.id] = mark;
      result.add(marker);
    }
    return result;
  }

  void _onMarkerTap(String markerId) {
    final LocationMark? mark = _markerIndex[markerId];
    if (mark == null) return;
    setState(() => _selected = mark);
    _moveTo(mark);
  }

  void _moveTo(LocationMark mark) {
    final LatLngPair gcj =
        CoordinateConverter.wgs84ToGcj02(mark.latitude, mark.longitude);
    _controller?.moveCamera(
      CameraUpdate.newLatLng(LatLng(gcj.latitude, gcj.longitude)),
      animated: true,
    );
  }

  /// 打开时把所有点framed进视野：取包围盒中心，按跨度估一个缩放级别。
  CameraPosition _initialCamera() {
    if (_marks.isEmpty) {
      return const CameraPosition(
        target: LatLng(39.909187, 116.397451),
        zoom: 10,
      );
    }
    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final LocationMark mark in _marks) {
      final LatLngPair gcj =
          CoordinateConverter.wgs84ToGcj02(mark.latitude, mark.longitude);
      minLat = min(minLat, gcj.latitude);
      maxLat = max(maxLat, gcj.latitude);
      minLng = min(minLng, gcj.longitude);
      maxLng = max(maxLng, gcj.longitude);
    }
    final double span = max(maxLat - minLat, maxLng - minLng);
    return CameraPosition(
      target: LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2),
      zoom: zoomForSpan(span),
    );
  }

  /// 经纬度跨度 -> 缩放级别。跨度越大级别越小，限制在高德的 3~17 之间。
  static double zoomForSpan(double span) {
    if (span <= 0.0005) return 17;
    final double zoom = log(360 / span) / ln2;
    return zoom.clamp(3.0, 17.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全部标记'),
        actions: <Widget>[
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_marks.length} 个',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : Stack(
              children: <Widget>[
                Positioned.fill(child: _buildMap()),
                if (_selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: _MarkDrawer(
                      mark: _selected!,
                      onClose: () => setState(() => _selected = null),
                      onOpenDetail: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                MarkerDetailPage(mark: _selected!),
                          ),
                        );
                        await _load();
                      },
                      onNavigate: () => NavAppSheet.show(context, _selected!),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildMap() {
    return ValueListenableBuilder<bool>(
      valueListenable: AmapRuntime.instance.privacyAgreed,
      builder: (BuildContext context, bool agreed, _) {
        if (!AmapConfig.hasKey || !agreed) {
          return _MapUnavailable(
            reason: AmapConfig.hasKey
                ? '你还没有同意包含高德条款的隐私声明，地图无法加载'
                : '还没有配置高德地图 Key，地图无法加载',
            markCount: _marks.length,
          );
        }

        AmapRuntime.instance.initSdk(context);
        final AppSettings settings = SettingsController.instance.value;
        return AMapWidget(
          initialCameraPosition: _initialCamera(),
          markers: _markers,
          mapType: amapTypeOf(settings.mapKind),
          trafficEnabled: settings.showTraffic,
          touchPoiEnabled: false,
          onMapCreated: (AMapController controller) =>
              _controller = controller,
          onTap: (_) {
            if (_selected != null) setState(() => _selected = null);
          },
        );
      },
    );
  }
}

/// 点中标记后从底部升起的抽屉。
class _MarkDrawer extends StatelessWidget {
  const _MarkDrawer({
    required this.mark,
    required this.onClose,
    required this.onOpenDetail,
    required this.onNavigate,
  });

  final LocationMark mark;
  final VoidCallback onClose;
  final VoidCallback onOpenDetail;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<String>(mark.id),
      tween: Tween<double>(begin: 60, end: 0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double offset, Widget? child) =>
          Transform.translate(offset: Offset(0, offset), child: child),
      child: SectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (mark.photoPaths.isNotEmpty) ...<Widget>[
                  PhotoThumb(relativePath: mark.photoPaths.first, size: 64),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        mark.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        mark.addressOrCoordinate,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (mark.tags.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: <Widget>[
                            for (final String tag in mark.tags)
                              TagPill(tag: tag, dense: true),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(Icons.close,
                        size: 18, color: AppColors.textTertiary),
                  ),
                ),
              ],
            ),
            if (mark.note.isNotEmpty) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                mark.note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onNavigate,
                    icon: const Icon(Icons.navigation_outlined, size: 17),
                    label: const Text('导航'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.divider),
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: onOpenDetail,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(42),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                    ),
                    child: const Text('查看详情'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable({required this.reason, required this.markCount});

  final String reason;
  final int markCount;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.map_outlined,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 18),
            Text('地图暂时不可用',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              reason,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(
              '已记录 $markCount 个标记，可以回列表查看',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
