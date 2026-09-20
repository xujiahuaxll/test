import 'dart:async';

import 'package:flutter/material.dart';

import '../data/marker_repository.dart';
import '../data/settings_repository.dart';
import '../models/location_mark.dart';
import '../services/cloud_sync.dart';
import '../services/settings_controller.dart';
import '../services/sync_runner.dart';
import '../theme/app_theme.dart';
import '../widgets/marker_card.dart';
import '../widgets/nav_app_sheet.dart';
import 'add_marker_page.dart';
import 'marker_detail_page.dart';
import 'markers_map_page.dart';
import 'settings_page.dart';

/// 首页：从本地数据库读取标记列表，支持关键词搜索与标签筛选。
class MarkerListPage extends StatefulWidget {
  const MarkerListPage({super.key});

  @override
  State<MarkerListPage> createState() => _MarkerListPageState();
}

class _MarkerListPageState extends State<MarkerListPage> {
  final MarkerRepository _repo = MarkerRepository.instance;
  final TextEditingController _searchController = TextEditingController();

  List<LocationMark> _markers = <LocationMark>[];
  List<String> _tags = <String>[];
  String _activeTag = '全部';
  String _keyword = '';
  bool _loading = true;
  int _total = 0;
  Timer? _debounce;

  /// 云端三项齐全才显示同步按钮。
  bool _cloudReady = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_reload);
    // 设置页改了排序方式后列表要跟着重排。
    SettingsController.instance.addListener(_reload);
    _reload();
    _refreshCloudReady();
  }

  @override
  void dispose() {
    _repo.removeListener(_reload);
    SettingsController.instance.removeListener(_reload);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final List<LocationMark> markers = await _repo.query(
      keyword: _keyword,
      tag: _activeTag == '全部' ? null : _activeTag,
      sort: SettingsController.instance.value.markerSort,
    );
    final List<String> tags = await _repo.allTags();
    final int total = await _repo.count();
    if (!mounted) return;
    setState(() {
      _markers = markers;
      _tags = tags;
      _total = total;
      _loading = false;
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      _keyword = value;
      _reload();
    });
  }

  Future<void> _openAdd() async {
    await Navigator.of(context).push(
      MaterialPageRoute<LocationMark>(builder: (_) => const AddMarkerPage()),
    );
    await _reload();
  }

  Future<void> _openMap() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const MarkersMapPage()),
    );
    await _reload();
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const SettingsPage()),
    );
    await _reload();
    await _refreshCloudReady();
  }

  /// 走一次同步：拉取 -> 报差异 -> 用户选策略 -> 落地。
  ///
  /// 中间那次确认不能省。三种策略里两种会删数据，而删掉的照片和录音
  /// 是找不回来的——得让用户看清各删多少条再点。
  Future<void> _sync() async {
    final SettingsRepository repo = SettingsRepository.instance;
    final String api =
        (await repo.getString(SettingsRepository.keyCloudApi) ?? '').trim();
    final String account =
        (await repo.getString(SettingsRepository.keyCloudAccount) ?? '').trim();
    final String password =
        (await repo.getString(SettingsRepository.keyCloudPassword) ?? '').trim();
    if (api.isEmpty || account.isEmpty || password.isEmpty) {
      _toast('请先到设置里填好云端地址、手机号和密码');
      return;
    }

    setState(() => _syncing = true);
    final CloudSync cloud =
        CloudSync(baseUrl: api, account: account, password: password);
    final SyncRunner runner = SyncRunner(cloud: cloud);
    try {
      final SyncPreparation prep = await runner.prepare();
      if (!mounted) return;

      if (prep.diff.isEmpty) {
        _toast('两边已经一致，没有要同步的');
        return;
      }
      final SyncStrategy? strategy = await showModalBottomSheet<SyncStrategy>(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _SyncSheet(diff: prep.diff),
      );
      if (strategy == null || !mounted) return;

      final SyncOutcome outcome = await runner.apply(prep, strategy);
      if (!mounted) return;
      await _reload();
      if (mounted) _toast('同步完成：${outcome.describe()}');
    } on CloudFailure catch (e) {
      if (mounted) _toast(e.message);
    } finally {
      cloud.close();
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refreshCloudReady() async {
    final SettingsRepository repo = SettingsRepository.instance;
    final bool ready = <String>[
          SettingsRepository.keyCloudApi,
          SettingsRepository.keyCloudAccount,
          SettingsRepository.keyCloudPassword,
        ].length ==
        (await Future.wait(<Future<String?>>[
          repo.getString(SettingsRepository.keyCloudApi),
          repo.getString(SettingsRepository.keyCloudAccount),
          repo.getString(SettingsRepository.keyCloudPassword),
        ]))
            .where((String? v) => (v ?? '').trim().isNotEmpty)
            .length;
    if (!mounted) return;
    setState(() => _cloudReady = ready);
  }

  Future<void> _openDetail(LocationMark mark) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MarkerDetailPage(mark: mark)),
    );
    await _reload();
  }

  Future<void> _confirmDelete(LocationMark mark) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('删除标记'),
        content: Text('确定删除「${mark.name}」吗？照片和录音会一起删除。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repo.delete(mark);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: _reload,
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: _Header(
                  total: _total,
                  onOpenMap: _openMap,
                  onOpenSettings: _openSettings,
                  onSync: _cloudReady ? _sync : null,
                  syncing: _syncing,
                ),
              ),
              SliverToBoxAdapter(
                child: _SearchBar(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                ),
              ),
              SliverToBoxAdapter(
                child: _TagFilter(
                  tags: _tags,
                  active: _activeTag,
                  onSelected: (String tag) {
                    setState(() => _activeTag = tag);
                    _reload();
                  },
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 110),
                sliver: _loading
                    ? const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.only(top: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      )
                    : _markers.isEmpty
                        ? SliverToBoxAdapter(
                            child: _EmptyState(
                              hasFilter: _activeTag != '全部' ||
                                  _keyword.trim().isNotEmpty,
                              total: _total,
                            ),
                          )
                        : SliverList.separated(
                            itemCount: _markers.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 12),
                            itemBuilder: (BuildContext context, int index) {
                              final LocationMark mark = _markers[index];
                              return MarkerCard(
                                mark: mark,
                                onTap: () => _openDetail(mark),
                                onLongPress: () => _confirmDelete(mark),
                                onNavigate: () =>
                                    NavAppSheet.show(context, mark),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openAdd,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text(
          '添加标记',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.total,
    required this.onOpenMap,
    required this.onOpenSettings,
    this.onSync,
    this.syncing = false,
  });

  final int total;
  final VoidCallback onOpenMap;
  final VoidCallback onOpenSettings;

  /// 没配好云端时为 null，同步按钮就不显示——点了也没处发去。
  final VoidCallback? onSync;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('我的标记',
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  total == 0 ? '还没有记录任何地点' : '共 $total 个地点 · 全部保存在本机',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          if (onSync != null) ...<Widget>[
            _RoundIconButton(
              icon: Icons.sync,
              tooltip: '与云端同步',
              onTap: onSync!,
              busy: syncing,
            ),
            const SizedBox(width: 8),
          ],
          _RoundIconButton(
            icon: Icons.map_outlined,
            tooltip: '在地图上查看全部',
            onTap: onOpenMap,
          ),
          const SizedBox(width: 8),
          _RoundIconButton(
            icon: Icons.settings_outlined,
            tooltip: '设置',
            onTap: onOpenSettings,
          ),
        ],
      ),
    );
  }
}

/// 同步前让用户选策略。
///
/// 三种策略的后果差别很大，所以每一项都把「这一项会发生什么」当场算出来
/// 写在下面，而不是笼统写「同步」。会删数据的那两项还要标红——
/// 删掉的照片和录音找不回来。
class _SyncSheet extends StatelessWidget {
  const _SyncSheet({required this.diff});

  final SyncDiff diff;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text('这次要怎么同步',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                _summary(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final SyncStrategy s in SyncStrategy.values)
                _StrategyTile(
                  strategy: s,
                  outcome: diff.outcomeFor(s),
                  onTap: () => Navigator.of(context).pop(s),
                ),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _summary() {
    final List<String> bits = <String>[
      if (diff.onlyLocal.isNotEmpty) '本机独有 ${diff.onlyLocal.length} 条',
      if (diff.onlyServer.isNotEmpty) '云端独有 ${diff.onlyServer.length} 条',
      if (diff.localNewer.isNotEmpty) '本机较新 ${diff.localNewer.length} 条',
      if (diff.serverNewer.isNotEmpty) '云端较新 ${diff.serverNewer.length} 条',
    ];
    return bits.isEmpty ? '两边一致' : bits.join(' · ');
  }
}

class _StrategyTile extends StatelessWidget {
  const _StrategyTile({
    required this.strategy,
    required this.outcome,
    required this.onTap,
  });

  final SyncStrategy strategy;
  final SyncOutcome outcome;
  final VoidCallback onTap;

  bool get _deletes => outcome.localDeleted > 0 || outcome.remoteDeleted > 0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        strategy.label,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        outcome.describe(),
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: _deletes
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_deletes)
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: AppColors.danger)
                else
                  const Icon(Icons.chevron_right,
                      size: 18, color: AppColors.textTertiary),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.busy = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  /// 忙的时候换成转圈，并挡住重复点击——同步跑两遍会把差异算乱。
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppColors.surface,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: busy ? null : onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: 42,
            height: 42,
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primary,
                    ),
                  )
                : Icon(icon, size: 20, color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          boxShadow: kCardShadow,
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.search, size: 19, color: AppColors.textTertiary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: '搜索名称、备注或地址',
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
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
                      size: 17, color: AppColors.textTertiary),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TagFilter extends StatelessWidget {
  const _TagFilter({
    required this.tags,
    required this.active,
    required this.onSelected,
  });

  final List<String> tags;
  final String active;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final List<String> all = <String>['全部', ...tags];

    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          final String tag = all[index];
          final bool selected = tag == active;
          final Color color =
              tag == '全部' ? AppColors.primary : AppColors.tagColor(tag);

          return GestureDetector(
            onTap: () => onSelected(tag),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? color : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.pill),
                border: Border.all(
                  color: selected ? color : AppColors.divider,
                ),
              ),
              child: Text(
                tag,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.hasFilter, required this.total});

  final bool hasFilter;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Column(
        children: <Widget>[
          Container(
            width: 92,
            height: 92,
            decoration: const BoxDecoration(
              color: AppColors.primarySoft,
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasFilter ? Icons.search_off : Icons.explore_off_outlined,
              size: 40,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            hasFilter ? '没有符合条件的标记' : '还没有标记',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            hasFilter
                ? '换个关键词或标签试试'
                : total == 0
                    ? '点右下角「添加标记」记录第一个地方吧'
                    : '',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
