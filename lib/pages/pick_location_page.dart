import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../services/amap_runtime.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';
import '../utils/coordinate.dart';

/// 在高德地图上手动选点。拖动地图，屏幕中心就是选中的位置。
/// 返回的坐标已转回 WGS-84，与库里的存储口径一致。
class PickLocationPage extends StatefulWidget {
  const PickLocationPage({
    super.key,
    required this.initialLatitude,
    required this.initialLongitude,
  });

  /// WGS-84 起始点。
  final double initialLatitude;
  final double initialLongitude;

  static Future<LocationResult?> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<LocationResult>(
        builder: (_) => PickLocationPage(
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );
  }

  @override
  State<PickLocationPage> createState() => _PickLocationPageState();
}

class _PickLocationPageState extends State<PickLocationPage> {
  late LatLngPair _wgs =
      LatLngPair(widget.initialLatitude, widget.initialLongitude);
  String? _address;
  bool _resolving = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _resolveAddress();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onCameraMoveEnd(CameraPosition position) {
    // 地图给的是 GCJ-02，转回 WGS-84 再记下来。
    _wgs = CoordinateConverter.gcj02ToWgs84(
      position.target.latitude,
      position.target.longitude,
    );
    setState(() {
      _address = null;
      _resolving = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _resolveAddress);
  }

  Future<void> _resolveAddress() async {
    setState(() => _resolving = true);
    String? address;
    try {
      final List<Placemark> marks = await Geocoding().placemarkFromCoordinates(
        _wgs.latitude,
        _wgs.longitude,
        locale: const Locale('zh', 'CN'),
      );
      if (marks.isNotEmpty) {
        address = LocationService.formatPlacemark(marks.first);
      }
    } catch (_) {
      address = null;
    }
    if (!mounted) return;
    setState(() {
      _address = address;
      _resolving = false;
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      LocationResult(
        latitude: _wgs.latitude,
        longitude: _wgs.longitude,
        accuracy: 0,
        address: _address,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(
      widget.initialLatitude,
      widget.initialLongitude,
    );

    AmapRuntime.instance.initSdk(context);

    return Scaffold(
      appBar: AppBar(title: const Text('手动选择位置')),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AMapWidget(
              initialCameraPosition: CameraPosition(
                target: LatLng(gcj.latitude, gcj.longitude),
                zoom: 17,
              ),
              onCameraMoveEnd: _onCameraMoveEnd,
              touchPoiEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,
            ),
          ),
          // 屏幕中心的固定图钉：地图动、针不动。
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 34),
              child: _CenterPin(),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: _AddressPanel(
              address: _address,
              resolving: _resolving,
              coordinate: '${_wgs.latitude.toStringAsFixed(6)}, '
                  '${_wgs.longitude.toStringAsFixed(6)}',
              onConfirm: _confirm,
            ),
          ),
        ],
      ),
    );
  }
}

class _CenterPin extends StatelessWidget {
  const _CenterPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 40,
          height: 40,
          decoration: const BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.place, color: Colors.white, size: 22),
        ),
        const SizedBox(height: 2),
        Container(width: 3, height: 12, color: AppColors.primaryDark),
      ],
    );
  }
}

class _AddressPanel extends StatelessWidget {
  const _AddressPanel({
    required this.address,
    required this.resolving,
    required this.coordinate,
    required this.onConfirm,
  });

  final String? address;
  final bool resolving;
  final String coordinate;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: kCardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Icon(Icons.place, size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: resolving
                    ? Text(
                        '正在解析地址…',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      )
                    : Text(
                        address?.isNotEmpty == true
                            ? address!
                            : '未获取到地址（将只记录坐标）',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            coordinate,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: onConfirm,
            child: const Text('使用这个位置'),
          ),
        ],
      ),
    );
  }
}
