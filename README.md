# 地点标记（Location Marker）

一个用 Flutter 写的**纯本地**地点记录 App：给一个地方拍照、打标签、写备注或说一段话，
自动记下当前位置。所有数据都存在手机本机，**不连任何服务端、没有账号、没有第三方 API Key**。

## 功能

- **标记列表**：按时间倒序，支持关键词搜索（名称 / 备注 / 地址 / 语音转写文字）和标签筛选；下拉刷新；长按删除。
- **新建标记**：进入页面自动定位 → 显示地址与经纬度、定位精度；填名称、选标签（可新建自定义标签）、加照片（拍照或相册，最多 9 张）、写备注。
- **备注两种输入方式**：
  - 文字输入；
  - 语音转文字：边录音边用系统语音识别出文字，实时显示；录完音频文件保留可播放，识别文字自动填进备注且可手动修改。
- **录音面板**：真实麦克风录音（AAC/m4a），波形由麦克风实时振幅驱动，可暂停/继续/取消；录音时采集的振幅包络会一并存库，播放时画的是这段录音自己的波形。
- **播放**：详情页与编辑页的播放条播放本地音频，可点波形跳转进度。
- **详情页**：照片轮播与全屏查看（双指缩放）、位置与坐标（一键复制）、语音备注 + 转写文字、备注、编辑、删除。
- **删除**：删标记时级联清掉标签、照片记录和本机上的照片 / 录音文件。

## 数据怎么存

| 内容 | 位置 |
| --- | --- |
| 标记、标签、照片索引 | 应用内置 SQLite（`sqflite`），库名 `location_marker.db` |
| 照片 | 应用私有目录 `photos/`，库里只存相对路径 |
| 录音 | 应用私有目录 `audio/`，库里只存相对路径 |

> 库里存相对路径而不是绝对路径：iOS 的应用沙盒目录在版本更新后会变，存绝对路径会全部失效。

表结构（`lib/data/app_database.dart`）：

- `markers`：id、名称、备注、地址、经纬度、精度、录音路径、录音时长、转写文字、波形包络、创建/更新时间
- `marker_tags`：标记与标签的关联（带 position，保留选择顺序）
- `marker_photos`：标记的照片（带 position，保留添加顺序）
- `tags`：可选标签表，首次建库写入 8 个预置标签，用户自定义标签也会登记进来

## 用到的系统能力（都不是对外服务）

| 能力 | 插件 | 说明 |
| --- | --- | --- |
| 定位 | `geolocator` | 系统 GPS / 网络定位 |
| 地址 | `geocoding` | 系统自带的逆地理编码（iOS CLGeocoder / Android Geocoder），**不需要 API Key**；拿不到地址时界面回落显示经纬度 |
| 拍照 / 相册 | `image_picker` | 系统相机与相册 |
| 录音 | `record` | 系统麦克风，录成 m4a |
| 语音转文字 | `speech_to_text` | 系统语音识别（iOS SFSpeechRecognizer / Android SpeechRecognizer），**不接任何云 ASR 服务** |
| 播放 | `just_audio` | 播放本机音频文件 |
| 权限 | `permission_handler` | 被永久拒绝时引导去系统设置 |

两点说明：

1. **地图**：显示真实地图瓦片必然要连地图服务商，按「不接对外 API」的要求这里没有接。位置卡片是 `CustomPaint` 画的示意图（`lib/widgets/fake_map.dart`），真实信息以地址 + 经纬度 + 精度呈现。以后要接高德/腾讯/OSM，替换这一个组件即可。
2. **录音与识别并行**：录音和语音识别同时打开麦克风，个别机型可能不允许。代码里做了降级——识别启不起来时只保存录音，面板上会提示「本机的语音识别不可用，这次只保存录音」，文字可以录完后手动补。

## 运行

```bash
flutter pub get
flutter run            # 连真机或模拟器
flutter test           # 数据层单元测试（sqflite ffi 内存库）
```

首次运行会向系统申请定位、麦克风、相机/相册权限。权限声明已经配好：

- Android：`android/app/src/main/AndroidManifest.xml`（定位、录音、相机、相册，含 Android 13+ 的 `READ_MEDIA_IMAGES`，以及 speech/相机的 `<queries>`），`minSdk = 23`
- iOS：`ios/Runner/Info.plist`（定位、麦克风、语音识别、相机、相册的用途说明）

## 代码结构

```
lib/
  main.dart                     入口：预热应用目录 + 建库
  models/location_mark.dart     标记模型（含行 <-> 对象转换）
  data/
    app_database.dart           SQLite 建表、预置标签
    marker_repository.dart      增删改查、搜索、标签、级联删除（ChangeNotifier 通知刷新）
  services/
    media_store.dart            照片/录音的本地落盘与相对路径解析
    location_service.dart       定位 + 逆地理编码 + 失败原因分类
    recorder_service.dart       录音（含振幅流）
    speech_service.dart         系统语音识别，静音断句后自动续听并拼接
  pages/
    marker_list_page.dart       列表、搜索、筛选
    add_marker_page.dart        新建 / 编辑
    marker_detail_page.dart     详情、看大图、删除
  widgets/                      卡片、标签、波形、播放条、录音面板、位置示意图
test/
  marker_repository_test.dart   数据层单元测试
```
