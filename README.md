# 地点标记（Location Marker）

一个用 Flutter 写的地点记录 App：给一个地方拍照、打标签、写备注或说一段话，自动记下当前位置。
**标记、照片、录音全部存在手机本地**，没有账号、没有自建服务端；地图部分接的是高德地图 SDK。

## 功能

- **标记列表**：按时间倒序，支持关键词搜索（名称 / 备注 / 地址 / 语音转写文字）和标签筛选；下拉刷新；长按删除。
- **新建标记**：进入页面自动定位 → 显示地址与经纬度、定位精度；填名称、选标签（可新建自定义标签）、加照片（拍照或相册，最多 9 张）、写备注。
- **备注两种输入方式**：
  - 文字输入；
  - 语音转文字：边录音边用系统语音识别出文字，实时显示；录完音频文件保留可播放，识别文字自动填进备注且可手动修改。
- **录音面板**：真实麦克风录音（AAC/m4a），波形由麦克风实时振幅驱动，可暂停/继续/取消；录音时采集的振幅包络会一并存库，播放时画的是这段录音自己的波形。
- **播放**：详情页与编辑页的播放条播放本地音频，可点波形跳转进度。
- **全局地图**：首页右上角地图图标进入，一张地图上显示全部标记，可缩放、拖动；点标记从底部升起抽屉，看名称、地址、标签、备注缩略，可直接导航或进详情；打开时自动把所有点框进视野。
- **导航**：列表每条的右侧、详情页底部、地图抽屉里都有导航按钮，点击唤起本机的高德 / 百度 / 腾讯地图（iOS 还支持苹果地图，Android 支持系统默认地图）。只装了一个就直接拉起，装了多个才让你选，一个都没装则提供复制坐标。
- **地图**：高德地图显示标记位置；新建标记时可以「手动调整」，在地图上拖动选点，实时反查地址。
- **详情页**：照片轮播与全屏查看（双指缩放）、高德地图与坐标（一键复制）、语音备注 + 转写文字、备注、编辑、删除。
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
| 地图 | `amap_map` | 高德地图 SDK，需要自己的 Key，见下方「高德地图」一节 |
| 唤起导航 | `url_launcher` | 用 scheme 拉起本机已安装的地图应用，本身不联网 |
| 拍照 / 相册 | `image_picker` | 系统相机与相册 |
| 录音 | `record` | 系统麦克风，录成 m4a |
| 语音转文字 | `speech_to_text` | 系统语音识别（iOS SFSpeechRecognizer / Android SpeechRecognizer），**不接任何云 ASR 服务** |
| 播放 | `just_audio` | 播放本机音频文件 |
| 权限 | `permission_handler` | 被永久拒绝时引导去系统设置 |

**录音与识别并行**：录音和语音识别同时打开麦克风，个别机型可能不允许。代码里做了降级——识别启不起来时只保存录音，面板上会提示「本机的语音识别不可用，这次只保存录音」，文字可以录完后手动补。

## 高德地图

地图用官方插件 `amap_map`（旧的 `amap_flutter_map` 不支持 Dart 3）。三件事需要注意：

### 1. 申请 Key 并配置（Key 不进仓库）

到 [高德开放平台](https://lbs.amap.com/) 新建 Key：Android 要填包名（`com.example.location_marker`）和签名 SHA1，iOS 要填 Bundle ID。然后：

```bash
cp android/amap.properties.example android/amap.properties   # 填入自己的 Key
./scripts/run.sh                                             # 等价于 flutter run，自动带上 Key
./scripts/run.sh build apk                                   # 其它子命令照常透传
```

`android/amap.properties` 已在 `.gitignore` 里。脚本把同一份 Key 通过 `--dart-define` 传给 Dart 侧，Gradle 也从这个文件读同一个值注入 `AndroidManifest` 的 `com.amap.api.v2.apikey`，两边不会配歪。

**没配 Key 也能跑**：地图组件会退回本地绘制的示意图（右下角标注原因），App 其它功能不受影响。

### 2. 坐标系：库里存 WGS-84，显示时转 GCJ-02

系统定位（`geolocator`）给的是 WGS-84，高德用的是 GCJ-02（火星坐标）。直接把 WGS-84 的点画到高德地图上会**偏出几百米**。

处理方式：数据库里统一存 WGS-84（标准坐标，复制出去能给任何地图用），只在与地图交互时转换——显示时 WGS-84 → GCJ-02，地图选点时 GCJ-02 → WGS-84（迭代反解到厘米级）。转换在 `lib/utils/coordinate.dart`，`test/coordinate_test.dart` 验证了偏移量级、往返精度、境外不偏移和偏移方向。

### 3. 唤起第三方导航的坐标系

各家地图收的坐标系不一样，传错会把人导到几百米外：

| 应用 | scheme | 坐标系 |
| --- | --- | --- |
| 高德 | `androidamap://navi` / `iosamap://navi` | GCJ-02（必须带 `dev=0` 声明已是 GCJ-02） |
| 百度 | `baidumap://map/direction` | 带 `coord_type=gcj02` 参数传 GCJ-02 |
| 腾讯 | `qqmap://map/routeplan` | GCJ-02 |
| 苹果地图 | `http://maps.apple.com/` | WGS-84（原始坐标，不能偏移） |
| Android 系统 | `geo:` | GCJ-02 |

链接组装在 `lib/services/navigation_launcher.dart`，`test/navigation_launcher_test.dart` 逐家核对了坐标系、关键参数和名称转义。

Android 11+ 和 iOS 需要显式声明才能探测到这些应用是否安装，已配好：`AndroidManifest` 的 `<queries>`（scheme + package）与 `Info.plist` 的 `LSApplicationQueriesSchemes`。

### 4. 隐私合规：不弹窗会白屏

高德要求使用地图前，先把「隐私政策已包含高德条款、已弹窗告知、已取得用户同意」三个状态告诉 SDK，**任一为 false 地图就白屏**。所以：

- 首次启动弹一次隐私声明（`lib/widgets/privacy_gate.dart`），用户的选择存进本地数据库的 `settings` 表；
- 同意后才调用 `AMapInitializer.updatePrivacyAgree(...)` 并创建地图实例；
- 选「暂不同意」也能正常用 App，地图显示为本地示意图。

上线前请把弹窗文案换成自己的隐私政策，并确保其中确实包含《高德开放平台隐私权政策》。

## 运行

```bash
flutter pub get
./scripts/run.sh       # 带上高德 Key 运行（等价于 flutter run）
flutter run            # 不带 Key 也能跑，地图显示为本地示意图
flutter test           # 单元测试 + widget 测试
```

首次运行会向系统申请定位、麦克风、相机/相册权限。权限声明已经配好：

- Android：`android/app/src/main/AndroidManifest.xml`（定位、录音、相机、相册，含 Android 13+ 的 `READ_MEDIA_IMAGES`，高德需要的 `INTERNET`/`ACCESS_NETWORK_STATE`/`ACCESS_WIFI_STATE`/`CHANGE_WIFI_STATE`，以及 speech/相机的 `<queries>`），`minSdk = 23`
- iOS：`ios/Runner/Info.plist`（定位、麦克风、语音识别、相机、相册的用途说明）

## 代码结构

```
lib/
  main.dart                     入口：预热应用目录、建库、恢复隐私同意状态
  config/amap_config.dart       高德 Key（编译期变量，不进仓库）
  utils/coordinate.dart         WGS-84 <-> GCJ-02 转换、球面距离
  models/location_mark.dart     标记模型（含行 <-> 对象转换）
  data/
    app_database.dart           SQLite 建表、版本升级、预置标签
    marker_repository.dart      增删改查、搜索、标签、级联删除（ChangeNotifier 通知刷新）
    settings_repository.dart    本地键值设置（隐私同意状态）
  services/
    media_store.dart            照片/录音的本地落盘与相对路径解析
    location_service.dart       定位 + 逆地理编码 + 失败原因分类
    recorder_service.dart       录音（含振幅流）
    speech_service.dart         系统语音识别，静音断句后自动续听并拼接
    amap_runtime.dart           高德 SDK 的 Key 注入与隐私合规状态
    navigation_launcher.dart    唤起本机地图应用导航（按目标应用转换坐标系）
  pages/
    marker_list_page.dart       列表、搜索、筛选
    add_marker_page.dart        新建 / 编辑
    marker_detail_page.dart     详情、看大图、删除
    markers_map_page.dart       全局地图：所有标记 + 点击抽屉
    pick_location_page.dart     在高德地图上拖动选点
  widgets/                      卡片、标签、波形、播放条、录音面板、地图组件、导航选择、隐私弹窗
test/
  marker_repository_test.dart   数据层单元测试
  settings_repository_test.dart 设置与数据库升级
  coordinate_test.dart          坐标系转换
  navigation_launcher_test.dart 各家导航链接组装
  marker_list_page_test.dart    列表页 widget 测试
  markers_map_page_test.dart    全局地图页
```
