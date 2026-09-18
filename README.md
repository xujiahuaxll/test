# 地点标记 App · UI Demo

一个用 Flutter 写的「地点标记」App 的**界面演示**版本：只有页面和交互动效，
没有接入真实的定位、相机、录音和语音识别，数据全部来自 `lib/data/demo_data.dart`。

## 页面

| 页面 | 文件 | 内容 |
| --- | --- | --- |
| 标记列表（首页） | `lib/pages/marker_list_page.dart` | 标题区、搜索框、标签横向筛选、标记卡片列表（照片/名称/地址/标签/语音时长/备注摘要）、空状态、右下角「添加标记」按钮 |
| 新建标记 | `lib/pages/add_marker_page.dart` | 进入自动「定位」→ 顶部地图卡片显示地址与经纬度；标记名称、标记标签（多选）、标记照片（横向添加/删除）、标记备注（文字输入 / 语音转文字双模式） |
| 录音面板 | `lib/widgets/record_sheet.dart` | 底部弹出：计时、实时波形动画、暂停/继续、完成后「转文字中」过渡 |
| 标记详情 | `lib/pages/marker_detail_page.dart` | 大图头图、名称标签时间、地图与坐标、语音播放条 + 转写文字、备注、照片列表、编辑/导航按钮 |

## 演示逻辑说明（都不是真功能）

- **自动定位**：进入新建页后延时 1.6 秒，把「正在获取当前位置…」切换成固定的地址和经纬度；右下角按钮可重新触发。
- **地图**：`lib/widgets/fake_map.dart` 用 `CustomPaint` 画出街区、路网、河道和坐标点，接真实地图 SDK 时整块替换即可。
- **照片**：没有图片资源，用渐变 + 图标占位（`DemoPhoto`）；点击「添加照片」弹出拍照/相册选项，选择后添加一张占位图。
- **录音**：计时器和波形都是动画模拟；点「完成」后返回一条固定的转写文字，自动填进备注，仍可手动编辑。
- **播放**：`VoicePlayerBar` 点击播放时把波形进度跑一遍，不播真实音频。

## 运行

仓库里只有 `pubspec.yaml` 和 `lib/`，各平台工程目录需要本地生成一次：

```bash
flutter create .          # 生成 android / ios / web 等平台目录
flutter pub get
flutter run               # 或 flutter run -d chrome 直接在浏览器里看
```

## 后续接真功能时的替换点

| 功能 | 建议依赖 | 替换位置 |
| --- | --- | --- |
| 定位 + 逆地理编码 | `geolocator` / `geocoding` 或高德、腾讯地图 SDK | `AddMarkerPage._locate()` |
| 地图显示 | `flutter_map`、`amap_flutter_map` 等 | `FakeMap` |
| 拍照 / 相册 | `image_picker` | `AddMarkerPage._addPhoto()` |
| 录音 | `record` / `flutter_sound` | `RecordSheet` |
| 语音转文字 | 系统 `speech_to_text` 或云端 ASR | `RecordSheet._finish()` |
| 音频播放 | `just_audio` / `audioplayers` | `VoicePlayerBar` |
| 本地存储 | `sqflite` / `isar` / `drift` | `DemoData` |
