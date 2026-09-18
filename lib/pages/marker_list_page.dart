import 'dart:async';

import 'package:flutter/material.dart';

import '../data/marker_repository.dart';
import '../models/location_mark.dart';
import '../theme/app_theme.dart';
import '../widgets/marker_card.dart';
import 'add_marker_page.dart';
import 'marker_detail_page.dart';

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

  @override
  void initState() {
    super.initState();
    _repo.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _repo.removeListener(_reload);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final List<LocationMark> markers = await _repo.query(
      keyword: _keyword,
      tag: _activeTag == '全部' ? null : _activeTag,
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
              SliverToBoxAdapter(child: _Header(total: _total)),
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
  const _Header({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('我的标记', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            total == 0 ? '还没有记录任何地点' : '共 $total 个地点 · 全部保存在本机',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
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
