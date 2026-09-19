import 'package:flutter/material.dart';

import '../services/amap_location_service.dart';
import '../services/amap_runtime.dart';
import '../services/city_directory.dart';
import '../services/location_service.dart';
import '../theme/app_theme.dart';

/// 选一个城市，用来把搜索范围收到城里。
///
/// 名单从高德取，不写在代码里：区划会变，写死就得跟着发版。
class CityPickerPage extends StatefulWidget {
  const CityPickerPage({super.key, this.current, this.located});

  /// 当前正在用的城市，列表里会打勾。
  final AmapDistrict? current;

  /// 定位所在的城市，放在最上面一行方便一键回到本地。
  final AmapDistrict? located;

  /// 返回 null 表示用户直接返回、什么都没改。
  static Future<CityPickResult?> show(
    BuildContext context, {
    AmapDistrict? current,
    AmapDistrict? located,
  }) {
    return Navigator.of(context).push<CityPickResult>(
      MaterialPageRoute<CityPickResult>(
        builder: (_) => CityPickerPage(current: current, located: located),
      ),
    );
  }

  @override
  State<CityPickerPage> createState() => _CityPickerPageState();
}

class _CityPickerPageState extends State<CityPickerPage> {
  final TextEditingController _controller = TextEditingController();

  List<CityGroup> _groups = const <CityGroup>[];
  String _keyword = '';
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _groups = CityDirectory.instance.cached ?? const <CityGroup>[];
    if (_groups.isEmpty) _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!AmapRuntime.instance.mapReady) {
      setState(() => _error = '没有可用的高德 Key，无法获取城市名单');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<CityGroup> groups =
          await CityDirectory.instance.load(AmapRuntime.instance.effectiveKey);
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _loading = false;
      });
    } on LocationFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = failure.message;
      });
    }
  }

  void _pick(AmapDistrict? city) =>
      Navigator.of(context).pop(CityPickResult(city));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('选择城市')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: TextField(
              controller: _controller,
              autofocus: false,
              onChanged: (String value) => setState(() => _keyword = value),
              decoration: InputDecoration(
                hintText: '搜索城市或省份',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
          ),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    final String? error = _error;
    if (error != null) {
      return _Hint(
        text: error,
        actionLabel: '重试',
        onAction: _load,
      );
    }
    if (_loading && _groups.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final List<Widget> header = <Widget>[
      ListTile(
        leading: const Icon(Icons.public, color: AppColors.textSecondary),
        title: const Text('不限城市'),
        subtitle: const Text('搜全国，同名的地方会多一些'),
        trailing: widget.current == null
            ? const Icon(Icons.check, color: AppColors.primary)
            : null,
        onTap: () => _pick(null),
      ),
      if (widget.located != null)
        ListTile(
          leading: const Icon(Icons.my_location, color: AppColors.primary),
          title: Text(widget.located!.name),
          subtitle: const Text('当前定位所在城市'),
          trailing: widget.current?.adcode == widget.located!.adcode
              ? const Icon(Icons.check, color: AppColors.primary)
              : null,
          onTap: () => _pick(widget.located),
        ),
      const Divider(height: 1, color: AppColors.divider),
    ];

    if (_groups.isEmpty) {
      return ListView(
        children: <Widget>[
          ...header,
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              '还没有取到城市名单，可以先用「不限城市」搜索。',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    }

    if (_keyword.trim().isNotEmpty) {
      final List<AmapDistrict> hits =
          CityDirectory.search(_groups, _keyword);
      if (hits.isEmpty) {
        return _Hint(text: '没有找到「${_keyword.trim()}」这个城市');
      }
      return ListView.separated(
        itemCount: hits.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: AppColors.divider, indent: 16),
        itemBuilder: (_, int i) => _cityTile(hits[i]),
      );
    }

    return ListView.builder(
      itemCount: _groups.length + header.length,
      itemBuilder: (BuildContext context, int index) {
        if (index < header.length) return header[index];
        final CityGroup group = _groups[index - header.length];
        return ExpansionTile(
          title: Text(group.province),
          shape: const Border(),
          collapsedShape: const Border(),
          initiallyExpanded: group.cities.any(
            (AmapDistrict c) => c.adcode == widget.current?.adcode,
          ),
          children: <Widget>[
            for (final AmapDistrict city in group.cities) _cityTile(city),
          ],
        );
      },
    );
  }

  Widget _cityTile(AmapDistrict city) {
    final bool selected = city.adcode.isNotEmpty &&
        city.adcode == widget.current?.adcode;
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      title: Text(
        city.name,
        style: TextStyle(
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          color: selected ? AppColors.primary : null,
        ),
      ),
      trailing: selected
          ? const Icon(Icons.check, size: 20, color: AppColors.primary)
          : null,
      onTap: () => _pick(city),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(text, textAlign: TextAlign.center),
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 选择结果。包一层是为了把「选了不限城市」和「直接返回」区分开——
/// 两者都是 null 的话，用户想取消反而会把城市清掉。
class CityPickResult {
  const CityPickResult(this.city);

  final AmapDistrict? city;
}
