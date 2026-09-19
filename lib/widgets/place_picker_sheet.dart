import 'package:flutter/material.dart';

import '../services/amap_location_service.dart';
import '../services/amap_runtime.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// 从附近的 POI 里挑一个作为这条标记的地点名。
///
/// 逆地理编码给出的「某路某号」对人没什么意义，用户记得住的是
/// 「某某大厦」「某某景区」。这里把附近地点按距离列出来让用户直接选。
class PlacePickerSheet extends StatefulWidget {
  const PlacePickerSheet({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  /// WGS-84 坐标。
  final double latitude;
  final double longitude;

  /// 打开选择面板，返回用户选中的地点名；取消时返回 null。
  static Future<String?> show(
    BuildContext context, {
    required double latitude,
    required double longitude,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => PlacePickerSheet(
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  @override
  State<PlacePickerSheet> createState() => _PlacePickerSheetState();
}

class _PlacePickerSheetState extends State<PlacePickerSheet> {
  AmapPlaces? _places;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final AmapPlaces places =
          await AmapLocationService.instance.nearbyPlaces(
        apiKey: AmapRuntime.instance.effectiveKey,
        latitude: widget.latitude,
        longitude: widget.longitude,
        radius: 500,
      );
      if (!mounted) return;
      setState(() => _places = places);
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() => _error = failure.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '选择附近地点',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  '按距离由近到远',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Flexible(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final String? error = _error;
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Column(
          children: <Widget>[
            const Icon(Icons.wifi_off_outlined,
                size: 34, color: AppColors.textTertiary),
            const SizedBox(height: 10),
            Text(
              error,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

    final AmapPlaces? places = _places;
    if (places == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 36),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final List<AmapPlace> items = places.places;
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Text(
          places.formatAddress.isEmpty
              ? '附近没有找到可选的地点'
              : '附近没有 POI，只能用这条地址：\n${places.formatAddress}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: items.length + (places.formatAddress.isEmpty ? 0 : 1),
      separatorBuilder: (_, __) => const Divider(
        height: 1,
        color: AppColors.divider,
        indent: 12,
        endIndent: 12,
      ),
      itemBuilder: (BuildContext context, int index) {
        // 最后一条给出完整地址，附近 POI 都不合适时可以选它
        if (index == items.length) {
          return ListTile(
            leading: const Icon(Icons.signpost_outlined,
                color: AppColors.textTertiary),
            title: Text(places.formatAddress),
            subtitle: const Text('使用完整地址'),
            onTap: () => Navigator.of(context).pop(places.formatAddress),
          );
        }
        final AmapPlace place = items[index];
        return ListTile(
          leading: const Icon(Icons.place_outlined, color: AppColors.primary),
          title: Text(place.title),
          subtitle: place.snippet.isEmpty
              ? null
              : Text(
                  place.snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          trailing: Text(
            place.distanceText,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          onTap: () => Navigator.of(context).pop(place.title),
        );
      },
    );
  }
}
