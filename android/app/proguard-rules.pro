# 只有在 android/gradle.properties 里把 shrink 设回 true 时才会用到。
# Flutter 的 Gradle 插件会自动把本文件加进 release 的 proguardFiles。
#
# 高德 SDK 以 JAR 发布，不带 consumer 规则，必须在这里手动 keep：
# 它的原生库用 JNI 按原始类名查找 Java 类，被改名就会 JNI abort。
-keep class com.amap.api.**{*;}
-keep class com.amap.**{*;}
-keep class com.autonavi.**{*;}
-keep class com.loc.**{*;}

# 插件自身的入口
-keep class com.amap.flutter.map.**{*;}

# 带 native 方法的类连类名一起保留（默认规则只保留方法名，不保留类名）
-keepclasseswithmembers class * {
    native <methods>;
}
