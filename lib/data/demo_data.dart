import 'package:flutter/material.dart';

import '../models/marker.dart';

/// 所有页面共用的静态假数据。正式开发时整体替换为本地数据库 / 接口。
class DemoData {
  /// Demo 的「当前时间」，保证列表里的相对时间稳定可预期。
  static final DateTime now = DateTime(2026, 5, 18, 16, 20);

  /// 标签候选池（添加页多选、列表页筛选共用）。
  static const List<String> allTags = <String>[
    '美食',
    '风景',
    '咖啡',
    '打卡',
    '露营',
    '拍照',
    '工作',
    '待办',
  ];

  static const DemoPhoto photoValley = DemoPhoto(
      <Color>[Color(0xFF7FB77E), Color(0xFF2F9E7E)], Icons.forest_outlined, '山谷');
  static const DemoPhoto photoNoodle = DemoPhoto(
      <Color>[Color(0xFFF7B267), Color(0xFFE2703A)],
      Icons.ramen_dining_outlined,
      '面馆');
  static const DemoPhoto photoLake = DemoPhoto(
      <Color>[Color(0xFF8ECAE6), Color(0xFF3B8ED0)], Icons.water_outlined, '湖面');
  static const DemoPhoto photoCafe = DemoPhoto(
      <Color>[Color(0xFFBCAAA4), Color(0xFF8D6E63)],
      Icons.local_cafe_outlined,
      '咖啡');
  static const DemoPhoto photoNight = DemoPhoto(
      <Color>[Color(0xFFCE93D8), Color(0xFF7E57C2)],
      Icons.nightlife_outlined,
      '夜色');
  static const DemoPhoto photoBuilding = DemoPhoto(
      <Color>[Color(0xFF90A4AE), Color(0xFF546E7A)],
      Icons.apartment_outlined,
      '楼宇');

  /// 添加页「选择照片」用的占位图池。
  static const List<DemoPhoto> photoPool = <DemoPhoto>[
    photoValley,
    photoNoodle,
    photoLake,
    photoCafe,
    photoNight,
    photoBuilding,
  ];

  static final List<LocationMark> markers = <LocationMark>[
    LocationMark(
      id: 'm1',
      name: '临江公园 · 观景台',
      tags: const <String>['风景', '拍照'],
      address: '浙江省杭州市西湖区北山街 78 号',
      latitude: 30.259924,
      longitude: 120.146515,
      createdAt: now.subtract(const Duration(minutes: 35)),
      photos: const <DemoPhoto>[photoValley, photoLake],
      note: '傍晚六点的光最好，台阶上人少，适合拍逆光。下次带广角镜头再来一次。',
      voiceNote: const VoiceNote(
        duration: Duration(seconds: 42),
        transcript: '观景台右侧有一条小路可以下到江边，走过去大概三分钟，那边没有围栏，注意安全。',
      ),
    ),
    LocationMark(
      id: 'm2',
      name: '老陈手工面',
      tags: const <String>['美食', '打卡'],
      address: '杭州市拱墅区大关路 12 号（菜市场东门旁）',
      latitude: 30.313277,
      longitude: 120.145203,
      createdAt: now.subtract(const Duration(hours: 5)),
      photos: const <DemoPhoto>[photoNoodle],
      note: '片儿川 18 块，加浇头 6 块。只收现金，晚上七点半就关门。',
      voiceNote: const VoiceNote(
        duration: Duration(seconds: 18),
        transcript: '老板说周二休息，下次别白跑。',
      ),
    ),
    LocationMark(
      id: 'm3',
      name: '云栖竹径露营点',
      tags: const <String>['露营', '风景'],
      address: '杭州市西湖区梅灵南路云栖竹径内',
      latitude: 30.182611,
      longitude: 120.087723,
      createdAt: now.subtract(const Duration(days: 2)),
      photos: const <DemoPhoto>[photoValley, photoLake, photoNight],
      note: '草地平整，边上有水源。周末要提前预约，车位只有十来个。',
    ),
    LocationMark(
      id: 'm4',
      name: '街角咖啡（二楼靠窗）',
      tags: const <String>['咖啡', '工作'],
      address: '杭州市上城区中山中路 205 号 2F',
      latitude: 30.244501,
      longitude: 120.168892,
      createdAt: now.subtract(const Duration(days: 4)),
      photos: const <DemoPhoto>[photoCafe],
      note: '插座在靠窗第二张桌子底下，网速还行，适合下午改方案。',
      voiceNote: const VoiceNote(
        duration: Duration(seconds: 27),
        transcript: '手冲耶加雪菲 38 元，续杯半价，店员说周末人多建议提前到。',
      ),
    ),
    LocationMark(
      id: 'm5',
      name: '客户办公楼 A 座前台',
      tags: const <String>['工作', '待办'],
      address: '杭州市滨江区江南大道 588 号 A 座',
      latitude: 30.208334,
      longitude: 120.211456,
      createdAt: now.subtract(const Duration(days: 6)),
      photos: const <DemoPhoto>[photoBuilding],
      note: '访客登记需要身份证，停车从 B2 入口进，前台可以盖章。',
    ),
    LocationMark(
      id: 'm6',
      name: '江边夜跑起点',
      tags: const <String>['打卡'],
      address: '杭州市滨江区闻涛路江堤入口',
      latitude: 30.196728,
      longitude: 120.196331,
      createdAt: DateTime(2026, 5, 6, 20, 15),
      photos: const <DemoPhoto>[photoNight],
      note: '单圈 4.2 公里，路灯全程有，终点有直饮水。',
    ),
  ];
}
