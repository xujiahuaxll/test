# 地点标记（Location Marker）

一个用 Flutter 写的地点记录 App：给一个地方拍照、打标签、写备注或说一段话，自动记下当前位置。
**标记、照片、录音全部存在手机本地**，没有账号、没有自建服务端；地图部分接的是高德地图 SDK。

## 功能

- **标记列表**：按时间倒序，支持关键词搜索（名称 / 备注 / 地址 / 语音转写文字）和标签筛选；下拉刷新；长按删除。
- **新建标记**：进入页面自动定位 → 显示地址与经纬度、定位精度；填名称、选标签（可新建自定义标签）、加照片（拍照，或从相册**一次选多张**，最多 9 张）、写备注。
- **备注两种输入方式**：
  - 文字输入；
  - 语音转文字：录完之后用**打进包里的离线模型**识别（全程不联网），文字自动填进备注且可手动修改，识别不理想还能点「重新识别」重来一遍。
- **录音面板**：真实麦克风录音（WAV，16 位单声道），波形由麦克风实时振幅驱动，可暂停/继续/取消；录音时采集的振幅包络会一并存库，播放时画的是这段录音自己的波形。点「完成」后就地转文字，转不出来也不影响录音本身。
- **播放**：详情页与编辑页的播放条播放本地音频，可点波形跳转进度。
- **全局地图**：首页右上角地图图标进入，一张地图上显示全部标记，可缩放、拖动；点标记从底部升起抽屉，看名称、地址、标签、备注缩略，可直接导航或进详情；打开时自动把所有点框进视野。
- **导航**：列表每条的右侧、详情页底部、地图抽屉里都有导航按钮，点击唤起本机的高德 / 百度 / 腾讯地图（iOS 还支持苹果地图，Android 支持系统默认地图）。只装了一个就直接拉起，装了多个才让你选（在设置里指定过默认应用就不再多问），一个都没装则提供复制坐标。出行方式（驾车 / 步行 / 骑行 / 公交）也在设置里选。
- **地图**：高德地图显示标记位置；新建标记时可以「手动调整」，在地图上拖动选点，实时反查地址。
- **详情页**：照片轮播与全屏查看（双指缩放）、高德地图与坐标（一键复制）、备注（文字在上）、照片、语音播放条（放在最后）、编辑、删除。
- **分享**：详情页右上角分享，生成一张带封面、地点名、地址、标签、备注和**二维码**的图片。二维码里是高德官方的 `uri.amap.com` 链接，对方长按识别就能用高德地图打开这个位置，**不用装这个 App**。
  之所以把链接画成二维码：微信的分享接收界面只收图片，同一条分享里的文字会被直接丢掉，「又带图又带链接」在微信里只有这一条路。发短信 / 邮件 / Telegram 时那段文字照样带着。
- **设置**：首页右上角齿轮进入，把导航、地图、定位、录音转写、照片、列表排序的行为都集中到一页配置，改完立刻生效并存进内置数据库。
- **删除**：删标记时级联清掉标签、照片记录和本机上的照片 / 录音文件。

## 数据怎么存

| 内容 | 位置 |
| --- | --- |
| 标记、标签、照片索引 | 应用内置 SQLite（`sqflite`），库名 `location_marker.db` |
| 照片 | 应用私有目录 `photos/`，库里只存相对路径 |
| 录音 | 应用私有目录 `audio/`，库里只存相对路径 |

> 库里存相对路径而不是绝对路径：iOS 的应用沙盒目录在版本更新后会变，存绝对路径会全部失效。

表结构（`lib/data/app_database.dart`）：

- `markers`：id、名称、备注、**地点名 + 详细地址**、经纬度、精度、录音路径、录音时长、转写文字、波形包络、创建/更新时间
  （地点名「中铁吉盛」做标题，详细地址「北京市大兴区天河北路5号」做副标题；v3 加的列，旧数据为 null 时回落用地址当标题）
- `marker_tags`：标记与标签的关联（带 position，保留选择顺序）
- `marker_photos`：标记的照片（带 position，保留添加顺序）
- `tags`：可选标签表，首次建库写入 8 个预置标签，用户自定义标签也会登记进来
- `settings`：键值表，存高德隐私声明的同意状态和设置页的全部配置项

## 用到的系统能力（都不是对外服务）

| 能力 | 插件 | 说明 |
| --- | --- | --- |
| 定位 | 高德定位 SDK / `geolocator` | 配了 Key 走高德（自建 MethodChannel），否则系统定位；见下 |
| 地址 | `geocoding` | 系统自带的逆地理编码（iOS CLGeocoder / Android Geocoder），**不需要 API Key**；拿不到地址时界面回落显示经纬度 |
| 地图 | `amap_map` | 高德地图 SDK，需要自己的 Key，见下方「高德地图」一节 |
| 唤起导航 | `url_launcher` | 用 scheme 拉起本机已安装的地图应用，本身不联网 |
| 拍照 / 相册 | `image_picker` | 系统相机与相册 |
| 录音 | `record` | 系统麦克风，录成 WAV（16 位单声道）；机型不支持 WAV 时回落 AAC/m4a |
| 语音转文字 | `sherpa_onnx` + 本地 Paraformer 小模型 | **完全离线**，模型随 APK 发，识别不发任何网络请求 |
| 分享 | `share_plus` + `qr` | 系统分享面板；二维码用纯 Dart 的 `qr` 自己画进图里 |
| 播放 | `just_audio` | 播放本机音频文件 |
| 权限 | `permission_handler` | 被永久拒绝时引导去系统设置 |

### 语音转文字为什么改成「录完再转」

之前用的是系统语音识别（`speech_to_text`）。它在 Android 上走 `SpeechRecognizer`，
**只认实时麦克风输入**，没法识别已经录好的文件；而 `record` 录音时抢的是
`MediaRecorder.AudioSource.DEFAULT`。两个都要独占麦克风，同时开必然有一个起不来——
表现就是「只转了第一段，后面全没了」。这条路本身走不通，不是参数没调对。

现在换成本地离线模型：录音照常录，录完把 WAV 喂给模型。两件事不再抢麦克风。
代价是文字要等录完才出来（实时要流式模型，最小的也有 437 MB，装进 APK 不现实），
以及小模型难免有错字——所以转写结果做成可编辑的，旁边还有「重新识别」。

| | |
| --- | --- |
| 模型 | `sherpa-onnx-paraformer-zh-small-2024-03-09` |
| 运行时文件 | `model.int8.onnx` 78 MB + `tokens.txt` 74 KB |
| 在仓库里吗 | **不在**。构建前由 `scripts/fetch-asr-model.sh` 下载到 `assets/asr/` |
| 装机占用 | 约 156 MB（assets 里一份 + 首次启动复制到应用目录一份）|
| 支持的 CPU | arm64-v8a 与 armeabi-v7a；x86/x86_64 已被 `abiFilters` 排除（只有模拟器用得上，带上白白多 61 MB）|

为什么要复制一份出来：ONNX Runtime 要的是**文件路径**，读不了 Flutter 的 assets
（那是打包在 APK 里的压缩条目，没有独立的文件系统路径）。

识别跑在单独的 isolate 里（纯 CPU 的同步活，放主线程界面会整个卡住），
模型只加载一次，离开编辑页时把那个 isolate 放掉——一个记地点的 App
常驻几百兆内存迟早被系统杀掉。

模型缺失 / 加载失败 / 识别失败时，**录音功能本身不受影响**，
面板和编辑页都会说明原因，文字可以手打。

## 设置项

首页右上角的齿轮进入设置页。每一项都直接接在对应功能上，没有摆着不生效的开关；
改动立刻写进内置数据库的 `settings` 表，下次启动仍在。

| 分组 | 配置项 | 作用 |
| --- | --- | --- |
| 导航 | 默认导航应用 | 选定后点导航直接唤起它，不再弹选择面板；默认「每次询问」 |
| 导航 | 出行方式 | 驾车 / 步行 / 骑行 / 公交，按各家地图的参数分别映射（高德 `t`、百度 `mode`、腾讯 `type`、苹果 `dirflg`） |
| 地图 | 底图样式 | 标准 / 卫星 / 夜间，对应高德的 `MapType` |
| 地图 | 实时路况 | 在全局地图上叠加拥堵图层 |
| 地图 | 同意高德隐私声明 | 可以随时撤回；撤回后地图退回本地示意图。没配 Key 时置灰 |
| 地图 | 高德地图 Key | 点开填自己的 Key，存本机；空着则用打包时内置的 |
| 地图 | 应用包名 / 签名 SHA1 | 只读，点一下复制。登记高德 Key 要填这两个。这里显示的是**证书**指纹，只跟签名用的 keystore 走，换一版包不会变；填错或换了 keystore 没改绑才报 1009 |
| 定位 | 定位精度 | 高精度 / 均衡 / 省电，对应 `LocationAccuracy` 的三档 |
| 定位 | 定位超时 | 10 / 20 / 30 / 60 秒 |
| 定位 | 自动解析地址 | 关掉就只记经纬度，不调系统逆地理编码 |
| 备注与录音 | 离线语音转文字 | 只读，显示本机的语音模型是否可用 |
| 备注与录音 | 录音音质 | 省空间 16kHz / 标准 22kHz / 高音质 44kHz（WAV 不压缩，体积只由采样率决定）|
| 照片 | 保存质量 | 省空间 70%·1280 / 标准 85%·2048 / 原图不压缩 |
| 列表 | 默认排序 | 最近添加在前 / 最早添加在前 / 按名称排列 |
| 存储 | 照片与录音占用 | 统计两个媒体目录的文件数与体积 |
| 存储 | 清理未引用文件 | 删掉已经没有标记引用的照片和录音（删除中断或旧版本留下的孤儿文件） |
| 其他 | 系统权限设置 | 跳系统设置页管理定位 / 麦克风 / 相机 / 相册授权 |
| 其他 | 恢复默认设置 | 只重置配置项，标记数据不动 |

读写的入口：`lib/models/app_settings.dart`（全部配置项与序列化）、
`lib/services/settings_controller.dart`（全局持有者，启动时读一次）、
`lib/pages/settings_page.dart`（界面）。认不出或越界的存储值一律回落到默认，
所以手工改过库、或从旧版本升上来都不会让 App 起不来。

## 高德地图

地图用官方插件 `amap_map`（旧的 `amap_flutter_map` 不支持 Dart 3）。三件事需要注意：

Key 有两个来源，**运行时用户填的优先**：

| 来源 | 存哪 | 适合 |
| --- | --- | --- |
| 用户在设置页填的 | 本机数据库的 `settings` 表 | 同一个 APK 发给不同的人，各自用自己的 Key |
| 打包时注入的 | `--dart-define=AMAP_ANDROID_KEY=…` | 自己用、或给一批人配一个默认 Key |

两个都没有时地图退回本地绘制的示意图（标注原因），App 其它功能不受影响。

### 1. 用户在 App 里填自己的 Key

设置 → 地图 → 高德地图 Key，点开粘贴 32 位的 Key，保存即生效
（下次打开地图时 `MapsInitializer.setApiKey` 会收到新 Key）。清空保存则撤回，
回到打包时内置的 Key。「恢复默认设置」不会清掉它。

**这条路要求安装包的签名是固定的**，见下面的「签名」一节。

### 2. 打包时注入默认 Key（Key 不进仓库）

到 [高德开放平台](https://lbs.amap.com/) 新建 Key：Android 要填包名
（`com.example.location_marker`）和签名 SHA1，iOS 要填 Bundle ID。然后：

```bash
cp android/amap.properties.example android/amap.properties   # 填入自己的 Key
./scripts/run.sh                                             # 等价于 flutter run，自动带上 Key
./scripts/run.sh build apk                                   # 其它子命令照常透传
```

`android/amap.properties` 已在 `.gitignore` 里。脚本把同一份 Key 通过 `--dart-define` 传给 Dart 侧，Gradle 也从这个文件读同一个值注入 `AndroidManifest` 的 `com.amap.api.v2.apikey`，两边不会配歪。

### 3. 签名：让用户能注册自己的 Key 的前提

高德 Key 绑定的是「包名 + 签名 SHA1」。

**先分清两个都叫 SHA1 的东西**，这是最容易绕进去的地方：

| | 是什么 | 会不会变 |
| --- | --- | --- |
| **证书 SHA1** | keystore 里那张证书的指纹。**高德要的是这个** | keystore 不换就永远不变，跟改了多少代码、发了多少版都无关 |
| APK 文件的 SHA1 | 这个 apk 文件本身的校验和（构建产物里那个 `app-release.apk.sha1`） | 每次构建都不一样，**和高德毫无关系** |

下面说的 SHA1 一律指证书 SHA1。

**用哪把签名是按文件在不在决定的**：`android/app/build.gradle.kts` 里
`hasReleaseKeystore = rootProject.file("key.properties").exists()`，
release 构建照这个二选一；CI 那边只在 Secret `ANDROID_KEYSTORE_BASE64`
非空时才写出 `android/key.properties`。

所以**没配 Secret 时**会退回 **debug 签名**，而 debug keystore 是构建机现场
生成的——每次换一台 CI runner 就是一个新的 SHA1，按上一版 APK 注册的 Key
立刻失效。配好下面那四个 Secret 之后就不会了：每次构建都用同一把 keystore，
证书 SHA1 固定，高德那边登记一次就不用再管。

**为什么签名和 Key 有关**：包名只是个字符串，谁都能填成
`com.example.location_marker` 来盗用你的 Key；而签名需要私钥，伪造不了。
所以高德用「包名 + 签名 SHA1」确认请求确实来自你本人编译的包，对不上就
返回错误码 1009。校验在高德服务端做。

要把同一个 APK 发给不同的人各自填 Key，先准备一个固定的 keystore：

```bash
bash scripts/make-release-key.sh
```

它会生成 `release.jks`、随机口令，并直接打印出要登记的 SHA1 和四个
GitHub Secret 的值。已存在同名文件时会拒绝覆盖——覆盖等于换私钥，
SHA1 会变，已登记的 Key 立刻失效。

手工做等价于：

```bash
keytool -genkey -v -keystore release.jks -keyalg RSA -keysize 2048 \
  -validity 10000 -alias release
keytool -list -v -keystore release.jks -alias release | grep SHA1   # 记下这个值
```

本地构建：把 keystore 放好，写一份 `android/key.properties`
（`storeFile` / `storePassword` / `keyAlias` / `keyPassword`，
`storeFile` 相对 `android/` 目录）。这个文件和 `*.jks` 都在 `.gitignore` 里。

CI 构建：在仓库 Settings → Secrets and variables → Actions 添加四个 Secret——
`ANDROID_KEYSTORE_BASE64`（`base64 -w0 release.jks` 的输出）、
`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`、`ANDROID_KEY_PASSWORD`。
配了就自动启用，没配则退回 debug 签名并在构建日志里给出警告。

不管走哪条路，构建日志的「打印签名 SHA1」一步都会输出这次用的证书指纹，
把它填到高德开放平台建 Key 时的「SHA1」栏里。

**证书 SHA1 只有这两种情况会变**，其余任何改动都不会动它：

1. 换了一把 keystore（重新跑 `make-release-key.sh` 生成新的）；
2. 那四个 Secret 里任何一个被删掉或改错，导致构建退回 debug 签名。

改代码、改版本号、加依赖、换 Flutter 版本——都不会让它变。

### 4. 不能开 R8（`shrink=false`）

`android/gradle.properties` 里有一行 `shrink=false`，**不要删**。

Flutter 3.47 的 Gradle 插件默认给 release 打开 R8。高德 SDK
（`com.amap.api:3dmap-location-search`）是以 **JAR** 而不是 AAR 发布的，
JAR 不携带 consumer ProGuard 规则，R8 于是把它的类改名重打包；而
`libAMapOpenMap.so`（即 `libAMapSDK_MAP_v10_1_200.so`，SONAME 是前者）的
`JNI_OnLoad` 按原始类名 `com/autonavi/amap/mapcore/MsgProcessor` 去
`FindClass`，拿到 null 后接着调 `GetStaticMethodID`，触发 JNI abort，
一打开地图就闪退：

```
JNI DETECTED ERROR IN APPLICATION: java_class == null
  in call to GetStaticMethodID
```

包体积 113MB 几乎全是高德的原生库，R8 根本不碰，混淆省下的那点 Java 代码
不值得冒这个险。想重新打开就把 `shrink` 改回 `true`，
`android/app/proguard-rules.pro` 里备好了需要的 keep 规则（未经实测）。

CI 有一步「校验高德的类没被混淆掉」，直接在产物的 dex 里找
`Lcom/autonavi/amap/mapcore/MsgProcessor;`，找不到就让构建失败——
不用真机也能拦住这个回归。

### 5. 坐标系：库里存 WGS-84，显示时转 GCJ-02

系统定位（`geolocator`）给的是 WGS-84，高德用的是 GCJ-02（火星坐标）。直接把 WGS-84 的点画到高德地图上会**偏出几百米**。

处理方式：数据库里统一存 WGS-84（标准坐标，复制出去能给任何地图用），只在与地图交互时转换——显示时 WGS-84 → GCJ-02，地图选点时 GCJ-02 → WGS-84（迭代反解到厘米级）。转换在 `lib/utils/coordinate.dart`，`test/coordinate_test.dart` 验证了偏移量级、往返精度、境外不偏移和偏移方向。

### 6. 定位优先用高德，系统定位兜底

`LocationService.buildLocationSettings` 在 Android 上强制
`AndroidSettings(forceLocationManager: true)`，并且**先要权限再取位置**。

geolocator 检测到 Google Play 服务时会默认改用 FusedLocationProvider，
而 `Geolocator.isLocationServiceEnabled()` 那条路径是去问 GMS 的
`SettingsClient.checkLocationSettings()`。国行机（比如小米）上 GMS 往往
缺失或不可用，这个调用失败就被当成「定位服务未开启」——于是定位明明开着
也提示未开启。更糟的是原来的代码把这个判断放在权限请求之前，卡在第一步，
权限框根本没机会弹出来。

现在的顺序是：请求权限 →（配了 Key 就先走高德定位）→ 回落系统
LocationManager → 只有它明确抛 `LocationServiceDisabledException`
（GPS 与网络定位都关着）才提示服务未开启。

**高德定位**：`amap_map` 插件只封装了地图 View，没有封装定位 SDK，但定位
SDK 的类随 `3dmap-location-search` 已经打进包里了。所以自己搭了一条
MethodChannel：

- 原生侧 `android/app/src/main/kotlin/.../AmapLocationHandler.kt` 调
  `AMapLocationClient`，通道名 `location_marker/amap_location`
- 清单里必须有 `<service android:name="com.amap.api.location.APSService"/>`，
  少了它高德定位起不来
- app 模块要再声明一次 `com.amap.api:3dmap-location-search`：插件模块里用的是
  `implementation`，只进运行时不进使用方的编译类路径。版本要和插件里一致
- 高德返回 GCJ-02，`AmapLocationService.parseResult` 转回 WGS-84 再存；
  不转的话保存的坐标会偏出几百米
- 定位后再走一次高德搜索 SDK 的逆地理编码（`GeocodeSearch`），取「地点名」
  而不是「某路某号」：优先楼宇 > 园区/景区 > 最近的 POI > 整句地址。
  搜索 SDK 的 Key 与隐私声明是独立的一套（`ServiceSettings`），不与地图、定位共用
- 点地址可以从附近 POI 里另选一个（`PlacePickerSheet`），坐标不变
- 地点名优先取**周边搜索**（`PoiSearch`，按距离排序）的最近结果，它能到
  「XX号楼」这一级；逆地理编码常常只到小区或街道，只用它补整句地址
- 手动选点页（`PickLocationPage`）顶部可搜索（`Inputtips` 输入提示），
  底部列出当前点附近的地点直接选；页面内部一路用 GCJ-02，只在返回时
  转一次 WGS-84，不再来回换算
- 只在「配了 Key 且已同意隐私声明」时启用；失败（除权限类外）自动回落系统定位

写 Kotlin 时有两个坑：`AMapLocationClientOption` 的 setter 是 builder 风格
（返回 option 自身），Kotlin 不会把它们识别成属性，必须写成显式的链式调用。

### 7. 唤起第三方导航的坐标系

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

需要 Flutter 3.47 或更高（`amap_map` 与 `geolocator_android` 要求 compileSdk 35+
和新版 Flutter Gradle 插件）。

```bash
bash scripts/fetch-asr-model.sh   # 下载离线语音模型（78 MB，只需跑一次）
flutter pub get
./scripts/run.sh       # 带上高德 Key 运行（等价于 flutter run）
flutter run            # 不带 Key 也能跑，地图显示为本地示意图
flutter test           # 单元测试 + widget 测试
```

不跑第一步也能编译能跑，只是录音转不出文字（设置页会显示「离线语音转文字：不可用」）。
CI 每次构建都会跑这个脚本，并在打包后校验模型确实进了 APK。

## 打包 APK

推到 `claude/location-marker-app-ui-cab78c` 分支会自动触发
`.github/workflows/build-apk.yml`，产物在该次运行的 Artifacts 里（`location-marker-apk`）。
也可以在 Actions 页面手动 `Run workflow`。

想让包里的地图能用，先在仓库 Settings → Secrets and variables → Actions
添加 `AMAP_ANDROID_KEY`。这个 Key 要绑定包名 `com.example.location_marker`
和证书 SHA1——SHA1 从构建日志的「打印签名 SHA1」那一步读，它直接从打出来的
APK 里取，是使用者实际拿到的那个签名。

配好「签名」一节那四个 Secret 之后，这个值每次构建都一样，登记一次就够了；
四个 Secret 缺任何一个都会退回 debug 签名，SHA1 随构建机变化，日志里也会
给出警告。

本地打包：

```bash
./scripts/run.sh build apk --release
```

首次运行会向系统申请定位、麦克风、相机/相册权限。权限声明已经配好：

- Android：`android/app/src/main/AndroidManifest.xml`（定位、录音、相机、相册，含 Android 13+ 的 `READ_MEDIA_IMAGES`，高德需要的 `INTERNET`/`ACCESS_NETWORK_STATE`/`ACCESS_WIFI_STATE`/`CHANGE_WIFI_STATE`，以及相机的 `<queries>`），`minSdk = 24`（Flutter 3.47 模板默认值，即 Android 7.0 及以上）
- iOS：`ios/Runner/Info.plist`（定位、麦克风、相机、相册的用途说明）

语音识别不再需要任何系统权限——模型在本机跑，不调用系统的语音识别服务。

## 代码结构

```
lib/
  main.dart                     入口：预热应用目录、建库、恢复隐私同意状态、读取配置
  config/amap_config.dart       高德 Key（编译期变量，不进仓库）
  utils/coordinate.dart         WGS-84 <-> GCJ-02 转换、球面距离
  models/
    location_mark.dart          标记模型（含行 <-> 对象转换）
    app_settings.dart           全部可配置项、默认值与键值序列化
    nav_app.dart                可唤起的地图应用枚举
  data/
    app_database.dart           SQLite 建表、版本升级、预置标签
    marker_repository.dart      增删改查、搜索、标签、级联删除（ChangeNotifier 通知刷新）
    settings_repository.dart    本地键值设置（隐私同意状态 + 设置页配置）
  services/
    media_store.dart            照片/录音的本地落盘与相对路径解析
    location_service.dart       定位 + 逆地理编码 + 失败原因分类
    recorder_service.dart       录音（含振幅流），WAV 优先、AAC 兜底
    asr_service.dart            离线语音识别：模型落地 + 常驻 isolate 里跑 sherpa-onnx
    amap_runtime.dart           高德 SDK 的 Key 注入与隐私合规状态
    navigation_launcher.dart    唤起本机地图应用导航（按目标应用转换坐标系与出行方式）
    settings_controller.dart    配置的全局持有者，启动时读一次，改动即时落库
  pages/
    marker_list_page.dart       列表、搜索、筛选
    add_marker_page.dart        新建 / 编辑
    marker_detail_page.dart     详情、看大图、删除
    markers_map_page.dart       全局地图：所有标记 + 点击抽屉
    pick_location_page.dart     在高德地图上拖动选点
    settings_page.dart          设置页：导航 / 地图 / 定位 / 录音 / 照片 / 列表 / 存储
  widgets/                      卡片、标签、波形、播放条、录音面板、地图组件、导航选择、隐私弹窗
test/
  marker_repository_test.dart   数据层单元测试
  settings_repository_test.dart 设置与数据库升级
  coordinate_test.dart          坐标系转换
  navigation_launcher_test.dart 各家导航链接组装
  marker_list_page_test.dart    列表页 widget 测试
  markers_map_page_test.dart    全局地图页
  app_settings_test.dart        配置项的默认值、序列化与异常值回落
  location_service_test.dart    定位参数组装（含强制 LocationManager）
  amap_location_service_test.dart 高德定位通道：坐标系转换与错误分类
  amap_config_test.dart         高德 Key 的取舍、格式校验与打码
  media_store_test.dart         媒体占用统计与孤儿文件清理
  settings_page_test.dart       设置页 widget 测试（改动要真的落库）
```

跑一遍：`flutter analyze && flutter test`（127 个测试）。
