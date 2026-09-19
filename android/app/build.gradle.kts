import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 高德 Key 从 android/amap.properties 读取（该文件不进仓库）。
// 没有这个文件时占位为空串，编译照常通过，地图会退回本地示意图。
val amapProperties = Properties()
val amapPropertiesFile = rootProject.file("amap.properties")
if (amapPropertiesFile.exists()) {
    FileInputStream(amapPropertiesFile).use { stream -> amapProperties.load(stream) }
}
val amapAndroidKey: String = amapProperties.getProperty("AMAP_ANDROID_KEY") ?: ""

// 正式签名从 android/key.properties 读（该文件和 keystore 都不进仓库）。
// 没有这个文件就退回 debug 签名，本地 `flutter run --release` 照常能跑。
//
// 为什么要在意：高德 Key 绑定「包名 + 签名 SHA1」。debug keystore 是构建机
// 现场生成的，换台机器（比如每次新的 CI runner）SHA1 就变，用户注册好的
// Key 会立刻失效。要把同一个 APK 发给不同的人各自填 Key，签名必须固定。
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { stream ->
        keystoreProperties.load(stream)
    }
}

android {
    namespace = "com.example.location_marker"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.location_marker"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["AMAP_ANDROID_KEY"] = amapAndroidKey
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file(
                    keystoreProperties.getProperty("storeFile"),
                )
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // 没配正式签名时退回 debug，签名 SHA1 会随构建机变化
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // MainActivity 里的 AmapLocationHandler 直接用了高德定位 SDK 的类。
    // 插件模块 third_party/amap_map 里声明的是 implementation，只进运行时
    // 不进使用方的编译类路径，所以这里要再声明一次。
    // 版本必须和插件里的保持一致，否则 Gradle 会解析出两个版本。
    implementation("com.amap.api:3dmap-location-search:10.1.200_loc6.4.9_sea9.7.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
