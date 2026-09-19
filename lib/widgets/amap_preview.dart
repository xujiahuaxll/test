import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../services/amap_runtime.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/coordinate.dart';
import 'fake_map.dart';

/// 只读的高德地图小窗：显示一个标记点。
///
/// 传进来的是库里存的 WGS-84 坐标，这里转成高德用的 GCJ-02 再显示。
/// 没配 Key 或用户还没同意隐私声明时，退回本地示意图，不会白屏。
class AMapPreview extends StatefulWidget {
  const AMapPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    this.zoom = 16,
    this.showHint = true,
  });

  /// WGS-84 坐标。
  final double latitude;
  final double longitude;
  final double zoom;

  /// 降级到示意图时是否提示原因。
  final bool showHint;

  @override
  State<AMapPreview> createState() => _AMapPreviewState();
}

class _AMapPreviewState extends State<AMapPreview> {
  AMapController? _controller;

  /// 坐标变了要把镜头挪过去。
  ///
  /// AMapWidget 的 initialCameraPosition 顾名思义只在创建时生效，重建时
  /// 传新坐标地图不会动——定位成功后地图会一直停在定位前的兜底位置，
  /// 看起来就是「地图和坐标对不上」。
  @override
  void didUpdateWidget(AMapPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      _moveCamera();
    }
  }

  void _moveCamera() {
    final AMapController? controller = _controller;
    if (controller == null) return;
    final LatLngPair gcj = CoordinateConverter.wgs84ToGcj02(
      widget.latitude,
      widget.longitude,
    );
    controller.moveCamera(
      CameraUpdate.newLatLng(LatLng(gcj.latitude, gcj.longitude)),
      animated: true,
    );
  }

  double get latitude => widget.latitude;
  double get longitude => widget.longitude;
  double get zoom => widget.zoom;
  bool get showHint => widget.showHint;

  @override
  Widget build(BuildContext context) {
    final AmapRuntime runtime = AmapRuntime.instance;
    // Key 和隐私同意状态任一变化都要重建：用户可能刚在设置页填完 Key。
    return ListenableBuilder(
      listenable: runtime.changes,
      builder: (BuildContext context, _) {
        if (!runtime.mapReady) {
          return _Fallback(
            latitude: latitude,
            longitude: longitude,
            showHint: showHint,
            reason: runtime.hasKey ? '待同意隐私声明' : '未配置高德 Key',
          );
        }

        runtime.initSdk(context);
        final LatLngPair gcj =
            CoordinateConverter.wgs84ToGcj02(latitude, longitude);
        final LatLng target = LatLng(gcj.latitude, gcj.longitude);

        return AMapWidget(
          initialCameraPosition:
              CameraPosition(target: target, zoom: zoom),
          onMapCreated: (AMapController controller) {
            _controller = controller;
            // 地图晚于定位结果创建时，这里把镜头对上。
            _moveCamera();
          },
          mapType:
              amapTypeOf(SettingsController.instance.value.mapKind),
          markers: <Marker>{
            Marker(position: target, infoWindowEnable: false),
          },
          scrollGesturesEnabled: false,
          zoomGesturesEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          touchPoiEnabled: false,
          scaleEnabled: false,
        );
      },
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({
    required this.latitude,
    required this.longitude,
    required this.showHint,
    required this.reason,
  });

  final double latitude;
  final double longitude;
  final bool showHint;
  final String reason;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        FakeMap(seed: ((latitude + longitude) * 1000).round()),
        if (showHint)
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                '示意图 · $reason',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
