# amap_map 本地补丁副本

源：pub.dev 上的 `amap_map` 1.0.15。

改动只有一处：`android/build.gradle` 的 `compileSdkVersion` 由 35 改为 36。

原因：上游写死 35，而 `flutter_plugin_android_lifecycle` 等依赖在 AAR metadata 里
要求使用方编译到 36，构建会在 `checkReleaseAarMetadata` 阶段失败。
反过来把那些依赖降级又会牵连出一串更老插件的 compileSdk 33 冲突，
所以选择把 amap_map 抬上来。

上游修复后即可删掉本目录，并去掉 `pubspec.yaml` 里的 `dependency_overrides`。
