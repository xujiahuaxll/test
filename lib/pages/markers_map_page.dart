import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../data/marker_repository.dart';
import '../models/app_settings.dart';
import '../models/location_mark.dart';
import '../services/amap_runtime.dart';
import '../services/media_store.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/coordinate.dart';
import '../utils/marker_icon.dart';
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
  List<String> _allTags = <String>[];

  /// 顶部快捷筛选选中的标签。null = 全部。
  String? _tagFilter;

  bool _loading = true;

  /// 地图 Marker 的 id -> 标记，点击回调只带回 id。
  final Map<String, LocationMark> _markerIndex = <String, LocationMark>{};

  /// 标记 id -> 地图 Marker 的 id。
  ///
  /// Marker 的 id 是构造时随机生成的，每次重建都换一个，插件就会把旧的全删
  /// 了再加一遍——选中态一闪一闪的。把 id 记下来沿用，插件只改图标。
  final Map<String, String> _markerIds = <String, String>{};

  /// 画好的图标，按「标签 + 封面 + 选中」缓存，同款标记共用一张。
  final Map<String, BitmapDescriptor> _iconCache =
      <String, BitmapDescriptor>{};

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
      tag: _tagFilter,
      sort: SettingsController.instance.value.markerSort,
    );
    final List<String> tags = await _repo.allTags();
    if (!mounted) return;
    setState(() {
      _marks = marks;
      _allTags = tags;
      _loading = false;
      // 刷新后原选中项可能已被删除，或者被筛选挡掉了
      if (_selected != null &&
          !marks.any((LocationMark m) => m.id == _selected!.id)) {
        _selected = null;
      }
      _markers = _composeMarkers(marks);
    });
    await _prepareIcons(marks);
  }

  /// 图标的缓存键。同标签、同封面的标记长得一模一样，画一张就够。
  static String iconKeyOf(LocationMark mark, bool selected) {
    final String cover =
        mark.photoPaths.isEmpty ? '' : mark.photoPaths.first;
    final String tag = mark.tags.isEmpty ? '' : mark.tags.first;
    return '$tag|$cover|${selected ? 's' : 'n'}';
  }

  Set<Marker> _composeMarkers(List<LocationMark> marks) {
    _markerIndex.clear();
    final Set<Marker> result = <Marker>{};
    for (final LocationMark mark in marks) {
      final bool selected = mark.id == _selected?.id;
      final LatLngPair gcj =
          CoordinateConverter.wgs84ToGcj02(mark.latitude, mark.longitude);
      final Marker marker = Marker(
        position: LatLng(gcj.latitude, gcj.longitude),
        icon: _iconCache[iconKeyOf(mark, selected)] ??
            BitmapDescriptor.defaultMarker,
        // 选中的那个压在最上面，不然会被旁边的点盖住
        zIndex: selected ? 20 : 1,
        infoWindowEnable: false,
        onTap: _onMarkerTap,
      );
      final String? previous = _markerIds[mark.id];
      if (previous != null) marker.setIdForCopy(previous);
      _markerIds[mark.id] = marker.id;
      _markerIndex[marker.id] = mark;
      result.add(marker);
    }
    return result;
  }

  /// 把还没画过的图标补齐，画完一次性刷上去。
  ///
  /// 选中态和未选中态一起画：等点下去再画会卡一下，而画一张图本来就比
  /// 解码封面图便宜得多——封面按 cover 路径去重，一张只解一次。
  Future<void> _prepareIcons(List<LocationMark> marks) async {
    final double ratio = MediaQuery.devicePixelRatioOf(context);
    final Map<String, ui.Image?> photos = <String, ui.Image?>{};
    bool changed = false;

    for (final LocationMark mark in marks) {
      final String cover =
          mark.photoPaths.isEmpty ? '' : mark.photoPaths.first;
      for (final bool selected in const <bool>[false, true]) {
        final String key = iconKeyOf(mark, selected);
        if (_iconCache.containsKey(key)) continue;
        if (cover.isNotEmpty && !photos.containsKey(cover)) {
          photos[cover] = await MarkerIcon.loadThumb(
            MediaStore.instance.absolute(cover),
          );
        }
        final Uint8List bytes = await MarkerIcon.render(
          color: AppColors.tagColor(mark.tags.isEmpty ? '' : mark.tags.first),
          photo: cover.isEmpty ? null : photos[cover],
          selected: selected,
          pixelRatio: ratio,
        );
        _iconCache[key] = BitmapDescriptor.fromBytes(bytes);
        changed = true;
      }
      if (!mounted) break;
    }

    for (final ui.Image? image in photos.values) {
      image?.dispose();
    }
    if (changed && mounted) {
      setState(() => _markers = _composeMarkers(_marks));
    }
  }

  void _onMarkerTap(String markerId) {
    final LocationMark? mark = _markerIndex[markerId];
    if (mark == null) return;
    _select(mark);
    _moveTo(mark);
  }

  /// 换选中项：图标要跟着换，不然点了哪个只有抽屉知道。
  void _select(LocationMark? mark) {
    if (_selected?.id == mark?.id) return;
    setState(() {
      _selected = mark;
      _markers = _composeMarkers(_marks);
    });
  }

  Future<void> _applyTagFilter(String? tag) async {
    if (_tagFilter == tag) return;
    // 这里刻意不把 _loading 打开：那会把整张地图换成转圈，AMapWidget 被
    // 销毁重建，视角也跟着回到原点。筛选只换一批 Marker，地图留着。
    setState(() => _tagFilter = tag);
    await _load();
    // 筛完剩下的点可能都在另一片区域，把视野重新框过去
    if (mounted && _marks.isNotEmpty) {
      _controller?.moveCamera(
        CameraUpdate.newCameraPosition(_initialCamera()),
        animated: true,
      );
    }
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
                if (_marks.isEmpty && _tagFilter != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        boxShadow: kCardShadow,
                      ),
                      child: Text('「$_tagFilter」下还没有标记'),
                    ),
                  ),
                if (_allTags.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 10,
                    child: _TagFilterBar(
                      tags: _allTags,
                      selected: _tagFilter,
                      onSelect: _applyTagFilter,
                    ),
                  ),
                if (_selected != null)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 16,
                    child: _MarkDrawer(
                      mark: _selected!,
                      onClose: () => _select(null),
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
    final AmapRuntime runtime = AmapRuntime.instance;
    return ListenableBuilder(
      listenable: runtime.changes,
      builder: (BuildContext context, _) {
        if (!runtime.mapReady) {
          return _MapUnavailable(
            reason: runtime.hasKey
                ? '你还没有同意包含高德条款的隐私声明，地图无法加载'
                : '还没有配置高德地图 Key，可以到设置页填自己的 Key',
            markCount: _marks.length,
          );
        }

        runtime.initSdk(context);
        final AppSettings settings = SettingsController.instance.value;
        return AMapWidget(
          initialCameraPosition: _initialCamera(),
          markers: _markers,
          mapType: amapTypeOf(settings.mapKind),
          trafficEnabled: settings.showTraffic,
          touchPoiEnabled: false,
          onMapCreated: (AMapController controller) =>
              _controller = controller,
          onTap: (_) => _select(null),
        );
      },
    );
  }
}

/// 顶部的标签快捷筛选条。
///
/// 横向可滑，点一下只看这个标签下的标记，再点一下回到全部。
class _TagFilterBar extends StatelessWidget {
  const _TagFilterBar({
    required this.tags,
    required this.selected,
    required this.onSelect,
  });

  final List<String> tags;
  final String? selected;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: tags.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return _Chip(
              label: '全部',
              color: AppColors.primary,
              active: selected == null,
              onTap: () => onSelect(null),
            );
          }
          final String tag = tags[index - 1];
          final bool active = tag == selected;
          return _Chip(
            label: tag,
            color: AppColors.tagColor(tag),
            active: active,
            // 再点一下取消筛选，不用特地去够最左边的「全部」
            onTap: () => onSelect(active ? null : tag),
          );
        },
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.color,
    required this.active,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? color : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(
            color: active ? color : AppColors.divider,
          ),
          boxShadow: kCardShadow,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w600 : FontWeight.w500,
            color: active ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
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
                        mark.displayTitle,
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
