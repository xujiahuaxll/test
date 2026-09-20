import 'dart:async';

import 'package:amap_map/amap_map.dart';
import 'package:flutter/material.dart';
import 'package:geocoding/geocoding.dart';
import 'package:x_amap_base/x_amap_base.dart';

import '../services/amap_location_service.dart';
import '../services/amap_runtime.dart';
import '../services/city_directory.dart';
import '../services/location_service.dart';
import '../services/settings_controller.dart';
import '../theme/app_theme.dart';
import '../utils/coordinate.dart';
import '../utils/place_ranking.dart';
import 'city_picker_page.dart';

/// 在高德地图上手动选点。
///
/// 三种定位方式，够不准的时候互相补：
/// 1. 拖地图，屏幕中心就是选中的位置；
/// 2. 顶部搜索，边打字边给候选，选中直接跳过去；
/// 3. 底部列出当前位置附近的地点，直接挑一个（拖不到楼门口时用这个）。
///
/// 地图给的是 GCJ-02，页面内部一路用 GCJ-02，只在最后返回时转成 WGS-84，
/// 与库里的存储口径一致。中间不再来回换算，少一道误差。
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
    return Navigator.of(context).push<LocationResult>(
      MaterialPageRoute<LocationResult>(
        builder: (_) => PickLocationPage(
          initialLatitude: latitude,
          initialLongitude: longitude,
        ),
      ),
    );
  }

  @override
  State<PickLocationPage> createState() => PickLocationPageState();
}

/// 公开是为了让相机回调的判定逻辑能被单测直接覆盖。
class PickLocationPageState extends State<PickLocationPage> {
  final TextEditingController _searchController = TextEditingController();

  /// 当前选中点，GCJ-02（与地图同一套坐标）。
  late LatLngPair _gcj;

  AMapController? _controller;

  String? _address;
  String? _placeName;
  bool _resolving = false;

  List<AmapPlace> _nearby = const <AmapPlace>[];
  String? _nearbyError;

  List<AmapPlace> _tips = const <AmapPlace>[];
  bool _searching = false;

  /// 搜索限定在哪个城市。null = 不限。
  AmapDistrict? _city;

  /// 定位/当前点所在的城市，城市选择器里放在最上面一行。
  AmapDistrict? _locatedCity;

  /// 用户手动选过城市之后就别再跟着地图跑了——
  /// 他明摆着要搜外地，拖一下就被拽回本地城市会很恼人。
  bool _cityPinned = false;

  Timer? _resolveDebounce;
  Timer? _searchDebounce;

  /// 每次相机停下都自增，用来丢弃过期请求的返回。
  int _requestSeq = 0;

  /// 我们自己调 moveCamera 时记下目标点。
  ///
  /// 程序化移动和用户拖动触发的是同一个 onCameraMoveEnd，不加区分的话，
  /// 「搜索选中 -> 挪图钉」会立刻被当成一次拖动，把刚选好的名字清掉。
  LatLngPair? _programmaticTarget;

  /// 判断这次相机停下是不是我们自己挪过去的。
  ///
  /// 用距离比对而不是布尔开关：万一某次移动没回调，开关会一直挂着，
  /// 之后真正的拖动就全被忽略了；用距离的话下一次拖动自然对不上，能自愈。
  static bool isOwnMove(LatLngPair at, LatLngPair? target) {
    if (target == null) return false;
    return CoordinateConverter.distanceInMeters(
          at.latitude,
          at.longitude,
          target.latitude,
          target.longitude,
        ) <
        20;
  }

  @override
  void initState() {
    super.initState();
    _gcj = CoordinateConverter.wgs84ToGcj02(
      widget.initialLatitude,
      widget.initialLongitude,
    );
    _refreshForCurrentPoint();
    _warmUpCities();
  }

  /// 后台先把城市名单取回来，用户点城市入口时就不用干等一次网络请求。
  void _warmUpCities() {
    if (!_amapReady || CityDirectory.instance.cached != null) return;
    CityDirectory.instance
        .load(AmapRuntime.instance.effectiveKey)
        .catchError((Object _) => const <CityGroup>[]);
  }

  @override
  void dispose() {
    _resolveDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool get _amapReady => AmapRuntime.instance.mapReady;

  void _onCameraMoveEnd(CameraPosition position) {
    final LatLngPair at = LatLngPair(
      position.target.latitude,
      position.target.longitude,
    );
    final LatLngPair? target = _programmaticTarget;
    _programmaticTarget = null;
    _gcj = at;

    // 自己挪的：用户刚选中的地点名要留着，不能当成一次新的拖动。
    if (isOwnMove(at, target)) return;

    setState(() {
      _address = null;
      _placeName = null;
      _resolving = true;
    });
    _resolveDebounce?.cancel();
    _resolveDebounce =
        Timer(const Duration(milliseconds: 400), _refreshForCurrentPoint);
  }

  /// 当前点变了：重新解析地址，并刷新附近地点列表。
  Future<void> _refreshForCurrentPoint() async {
    final int seq = ++_requestSeq;
    setState(() => _resolving = true);
    // 先拿附近地点：它按距离排序、楼宇也搜得到，最近那个就是最贴切的名字。
    // 逆地理编码只用来补那句完整地址。
    await _loadNearby(seq);
    await _resolveAddress(seq);
  }

  Future<void> _resolveAddress(int seq) async {
    String? placeName;
    String? address;

    if (_amapReady) {
      try {
        final AmapPlaces places =
            await AmapLocationService.instance.nearbyPlaces(
          apiKey: AmapRuntime.instance.effectiveKey,
          latitude: _gcj.latitude,
          longitude: _gcj.longitude,
          gcj: true,
        );
        placeName = places.bestName;
        address = places.formatAddress.isEmpty ? null : places.formatAddress;
        _rememberCity(places.cityDistrict);
        // 逆地理编码认不出落点在哪栋楼时，才拿周边搜索权重最高的那条顶上。
        // 这里原本是无条件用「最近的 POI」覆盖，而商户密度远高于楼宇，
        // 于是拖到哪儿都是「XX咖啡」——楼宇名明明已经拿到了却被盖掉。
        if (placeName == null && _nearby.isNotEmpty) {
          placeName = _nearby.first.title;
        }
      } on LocationFailure {
        // 高德不可用就往下走系统解析
      }
    }

    if (placeName == null && address == null) {
      final LatLngPair wgs = CoordinateConverter.gcj02ToWgs84(
        _gcj.latitude,
        _gcj.longitude,
      );
      try {
        final List<Placemark> marks =
            await Geocoding().placemarkFromCoordinates(
          wgs.latitude,
          wgs.longitude,
          locale: const Locale('zh', 'CN'),
        );
        if (marks.isNotEmpty) {
          address = LocationService.formatPlacemark(marks.first);
        }
      } catch (_) {
        address = null;
      }
    }

    if (!mounted || seq != _requestSeq) return;
    setState(() {
      _placeName = placeName;
      _address = address;
      _resolving = false;
    });
  }

  Future<void> _loadNearby(int seq) async {
    if (!_amapReady) {
      if (mounted && seq == _requestSeq) {
        setState(() {
          _nearby = const <AmapPlace>[];
          _nearbyError = '没有可用的高德 Key，无法列出附近地点';
        });
      }
      return;
    }
    try {
      final List<AmapPlace> places =
          await AmapLocationService.instance.nearbyPois(
        apiKey: AmapRuntime.instance.effectiveKey,
        latitude: _gcj.latitude,
        longitude: _gcj.longitude,
        radius: 500,
      );
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        // 建筑、站点排在店铺前面，和高德地图的顺序一致
        _nearby = PlaceRanking.rank(AmapPlace.dedupe(places));
        _nearbyError = null;
      });
    } on LocationFailure catch (failure) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _nearby = const <AmapPlace>[];
        _nearbyError = failure.message;
      });
    }
  }

  /// 记下当前点落在哪个城市。
  ///
  /// 用户手动选过城市之后就不再跟着地图跑：他明摆着要搜外地，
  /// 拖一下地图就被拽回本地城市会很恼人。
  void _rememberCity(AmapDistrict? city) {
    if (city == null || city.name.isEmpty) return;
    _locatedCity = city;
    if (!_cityPinned) _city = city;
  }

  Future<void> _openCityPicker() async {
    FocusScope.of(context).unfocus();
    final CityPickResult? picked = await CityPickerPage.show(
      context,
      current: _city,
      located: _locatedCity,
    );
    if (picked == null || !mounted) return;
    setState(() {
      _city = picked.city;
      // 选过一次就算钉住了，包括「不限城市」——那也是一个明确的选择。
      _cityPinned = true;
    });
    // 换了城市，旧的候选就不对了；还有词就按新范围重搜一遍。
    final String keyword = _searchController.text;
    if (keyword.trim().isEmpty) {
      setState(() => _tips = const <AmapPlace>[]);
    } else {
      _onSearchChanged(keyword);
    }
  }

  /// 城市入口上显示的字。还没解析出城市时先给个占位。
  String get cityLabel => _city?.name.isNotEmpty == true ? _city!.name : '全国';

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _tips = const <AmapPlace>[];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      if (!_amapReady) {
        if (mounted) setState(() => _searching = false);
        return;
      }
      try {
        final List<AmapPlace> tips =
            await AmapLocationService.instance.inputTips(
          apiKey: AmapRuntime.instance.effectiveKey,
          keyword: value,
          latitude: _gcj.latitude,
          longitude: _gcj.longitude,
          // 不限城市时搜「人民医院」会把全国的都列出来，翻十页也找不到
          // 身边那家；选了城市就只在城里找。
          city: _city?.adcode ?? '',
          cityLimit: _city != null,
        );
        if (!mounted) return;
        setState(() {
          _tips = tips;
          _searching = false;
        });
      } on LocationFailure {
        if (!mounted) return;
        setState(() {
          _tips = const <AmapPlace>[];
          _searching = false;
        });
      }
    });
  }

  /// 选中一个地点：图钉挪过去，名称与地址直接采用它的。
  Future<void> _selectPlace(AmapPlace place) async {
    FocusScope.of(context).unfocus();
    _searchController.clear();
    setState(() {
      _tips = const <AmapPlace>[];
      _placeName = place.title;
      // 候选没带地址时先清空，下面再补一条，别留着上一个点的地址不放
      _address = place.snippet.isEmpty ? null : place.snippet;
      _resolving = false;
    });

    if (!place.hasPoint) return;
    _gcj = LatLngPair(place.latitude!, place.longitude!);
    _programmaticTarget = _gcj;
    _controller?.moveCamera(
      CameraUpdate.newLatLng(LatLng(_gcj.latitude, _gcj.longitude)),
      animated: true,
    );

    // 挪过去之后刷新附近列表，但保留刚选中的名称
    final int seq = ++_requestSeq;
    await _loadNearby(seq);
    if (place.snippet.isEmpty) await _fillAddressOnly(seq);
  }

  /// 只补那句详细地址，不动已经选定的地点名。
  Future<void> _fillAddressOnly(int seq) async {
    if (!_amapReady) return;
    try {
      final AmapPlaces places = await AmapLocationService.instance.nearbyPlaces(
        apiKey: AmapRuntime.instance.effectiveKey,
        latitude: _gcj.latitude,
        longitude: _gcj.longitude,
        gcj: true,
      );
      if (!mounted || seq != _requestSeq) return;
      if (places.formatAddress.isNotEmpty) {
        setState(() => _address = places.formatAddress);
      }
    } on LocationFailure {
      // 补不上就只显示地点名，不影响确认
    }
  }

  void _confirm() {
    final LatLngPair wgs = CoordinateConverter.gcj02ToWgs84(
      _gcj.latitude,
      _gcj.longitude,
    );
    Navigator.of(context).pop(
      LocationResult(
        latitude: wgs.latitude,
        longitude: wgs.longitude,
        accuracy: 0,
        address: _address,
        placeName: _placeName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    AmapRuntime.instance.initSdk(context);

    return Scaffold(
      appBar: AppBar(title: const Text('手动选择位置')),
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AMapWidget(
              initialCameraPosition: CameraPosition(
                target: LatLng(_gcj.latitude, _gcj.longitude),
                zoom: 17,
              ),
              mapType: amapTypeOf(SettingsController.instance.value.mapKind),
              onMapCreated: (AMapController controller) =>
                  _controller = controller,
              onCameraMoveEnd: _onCameraMoveEnd,
              touchPoiEnabled: false,
              tiltGesturesEnabled: false,
              rotateGesturesEnabled: false,
            ),
          ),
          const Center(
            child: Padding(
              padding: EdgeInsets.only(bottom: 34),
              child: _CenterPin(),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            top: 12,
            child: _SearchBox(
              controller: _searchController,
              searching: _searching,
              tips: _tips,
              cityLabel: cityLabel,
              onPickCity: _openCityPicker,
              onChanged: _onSearchChanged,
              onPick: _selectPlace,
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: _PickPanel(
              placeName: _placeName,
              address: _address,
              resolving: _resolving,
              coordinate: '${_gcj.latitude.toStringAsFixed(6)}, '
                  '${_gcj.longitude.toStringAsFixed(6)}',
              nearby: _nearby,
              nearbyError: _nearbyError,
              onPickNearby: _selectPlace,
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

/// 顶部搜索框 + 候选列表。
class _SearchBox extends StatelessWidget {
  const _SearchBox({
    required this.controller,
    required this.searching,
    required this.tips,
    required this.cityLabel,
    required this.onPickCity,
    required this.onChanged,
    required this.onPick,
  });

  final TextEditingController controller;
  final bool searching;
  final List<AmapPlace> tips;

  /// 搜索限定的城市名，显示在输入框左边。
  final String cityLabel;
  final VoidCallback onPickCity;
  final ValueChanged<String> onChanged;
  final ValueChanged<AmapPlace> onPick;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 12),
            child: Row(
              children: <Widget>[
                // 城市入口：不收范围的话，搜「人民医院」会把全国的都列出来
                InkWell(
                  onTap: onPickCity,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 10,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 72),
                          child: Text(
                            cityLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down,
                            size: 20, color: AppColors.textSecondary),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 18,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: AppColors.divider,
                ),
                const Icon(Icons.search, size: 19,
                    color: AppColors.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onChanged,
                    textInputAction: TextInputAction.search,
                    decoration: const InputDecoration(
                      hintText: '搜索地点，如「双河北里27号楼」',
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 14),
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                if (searching)
                  const SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: controller,
                    builder: (BuildContext context, TextEditingValue value, _) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return GestureDetector(
                        onTap: () {
                          controller.clear();
                          onChanged('');
                        },
                        child: const Icon(Icons.close,
                            size: 18, color: AppColors.textTertiary),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
        if (tips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Material(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
              elevation: 2,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: tips.length,
                  separatorBuilder: (_, __) => const Divider(
                    height: 1,
                    color: AppColors.divider,
                    indent: 12,
                    endIndent: 12,
                  ),
                  itemBuilder: (BuildContext context, int index) {
                    final AmapPlace tip = tips[index];
                    return ListTile(
                      dense: true,
                      leading: const Icon(Icons.place_outlined,
                          size: 19, color: AppColors.primary),
                      title: Text(tip.title),
                      subtitle: tip.snippet.isEmpty
                          ? null
                          : Text(
                              tip.snippet,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      onTap: () => onPick(tip),
                    );
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 底部：当前选中的地点 + 附近可选列表 + 确认按钮。
class _PickPanel extends StatelessWidget {
  const _PickPanel({
    required this.placeName,
    required this.address,
    required this.resolving,
    required this.coordinate,
    required this.nearby,
    required this.nearbyError,
    required this.onPickNearby,
    required this.onConfirm,
  });

  final String? placeName;
  final String? address;
  final bool resolving;
  final String coordinate;
  final List<AmapPlace> nearby;
  final String? nearbyError;
  final ValueChanged<AmapPlace> onPickNearby;
  final VoidCallback onConfirm;

  String? get title {
    if (placeName?.isNotEmpty == true) return placeName;
    if (address?.isNotEmpty == true) return address;
    return null;
  }

  /// 标题已经是地点名时才补详细地址，避免两行一模一样。
  String? get subtitle =>
      placeName?.isNotEmpty == true && address?.isNotEmpty == true
          ? address
          : null;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            title ?? '未获取到地址（将只记录坐标）',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          if (subtitle != null) ...<Widget>[
                            const SizedBox(height: 3),
                            Text(
                              subtitle!,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppColors.textSecondary),
                            ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            coordinate,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppColors.textTertiary),
          ),
          const SizedBox(height: 10),
          _buildNearby(context),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: onConfirm,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('使用这个位置'),
          ),
        ],
      ),
    );
  }

  Widget _buildNearby(BuildContext context) {
    final String? error = nearbyError;
    if (error != null) {
      return Text(
        error,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppColors.accent),
      );
    }
    if (nearby.isEmpty) {
      return Text(
        '附近没有找到可选的地点',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          '拖得不够准时，直接从附近选一个',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 168),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: nearby.length,
            separatorBuilder: (_, __) => const Divider(
              height: 1,
              color: AppColors.divider,
            ),
            itemBuilder: (BuildContext context, int index) {
              final AmapPlace place = nearby[index];
              final bool selected = place.title == placeName;
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 19,
                  color:
                      selected ? AppColors.primary : AppColors.textTertiary,
                ),
                title: Text(
                  place.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
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
                onTap: () => onPickNearby(place),
              );
            },
          ),
        ),
      ],
    );
  }
}
