package com.example.location_marker

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 把高德定位 SDK 暴露给 Dart。
 *
 * amap_map 插件只封装了地图 View，没有封装定位；而定位 SDK 的类本来就
 * 随 3dmap-location-search 打进了包里，所以这里自己搭一条 MethodChannel。
 *
 * 相比系统定位的好处：国内精度更高、不依赖 Google Play 服务、一次调用
 * 直接连中文地址一起返回，省掉再做一次逆地理编码。
 */
class AmapLocationHandler(private val context: Context) {

    companion object {
        const val CHANNEL = "location_marker/amap_location"

        /** 高德要求先声明隐私合规状态，且必须在创建 client 之前。 */
        private var privacyDeclared = false
    }

    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "locate") {
            result.notImplemented()
            return
        }
        val apiKey = call.argument<String>("apiKey").orEmpty()
        if (apiKey.isEmpty()) {
            result.error("no_key", "没有可用的高德 Key", null)
            return
        }
        locate(
            apiKey = apiKey,
            timeoutMs = (call.argument<Int>("timeoutMs") ?: 20_000).toLong(),
            mode = call.argument<String>("mode") ?: "high",
            needAddress = call.argument<Boolean>("needAddress") ?: true,
            result = result,
        )
    }

    private fun locate(
        apiKey: String,
        timeoutMs: Long,
        mode: String,
        needAddress: Boolean,
        result: MethodChannel.Result,
    ) {
        // Dart 侧只在用户已经同意隐私声明时才会调到这里。
        if (!privacyDeclared) {
            AMapLocationClient.updatePrivacyShow(context, true, true)
            AMapLocationClient.updatePrivacyAgree(context, true)
            privacyDeclared = true
        }
        AMapLocationClient.setApiKey(apiKey)

        val client = try {
            AMapLocationClient(context)
        } catch (e: Exception) {
            result.error("client_failed", "高德定位初始化失败：${e.message}", null)
            return
        }

        // 一次定位只能回一次；SDK 回调和兜底超时都可能先到，用它保证只回一次。
        var replied = false
        var timeoutTask: Runnable? = null

        fun finish(action: () -> Unit) {
            main.post {
                if (replied) return@post
                replied = true
                timeoutTask?.let { main.removeCallbacks(it) }
                try {
                    client.stopLocation()
                    client.onDestroy()
                } catch (_: Throwable) {
                    // 释放失败不影响已经拿到的结果
                }
                action()
            }
        }

        // 注意用显式的 setter 链式调用：这些 setter 返回 option 自身
        // （builder 风格），Kotlin 不会把它们当成属性，写成 isOnceLocation = true
        // 是编译不过的。
        val option = AMapLocationClientOption()
            .setLocationMode(
                when (mode) {
                    "powerSave" ->
                        AMapLocationClientOption.AMapLocationMode.Battery_Saving
                    else ->
                        AMapLocationClientOption.AMapLocationMode.Hight_Accuracy
                }
            )
            .setOnceLocation(true)
            // 取一次最近的最优结果，比单次回调更稳
            .setOnceLocationLatest(true)
            .setNeedAddress(needAddress)
            .setGeoLanguage(AMapLocationClientOption.GeoLanguage.ZH)
            .setHttpTimeOut(timeoutMs)
        client.setLocationOption(option)

        client.setLocationListener { location: AMapLocation? ->
            if (location == null) {
                finish { result.error("null_location", "高德定位没有返回结果", null) }
                return@setLocationListener
            }
            if (location.errorCode != 0) {
                finish {
                    result.error(
                        "amap_${location.errorCode}",
                        location.errorInfo.orEmpty(),
                        location.locationDetail,
                    )
                }
                return@setLocationListener
            }
            finish {
                result.success(
                    mapOf(
                        // 高德返回的是 GCJ-02，转回 WGS-84 由 Dart 侧统一做
                        "latitude" to location.latitude,
                        "longitude" to location.longitude,
                        "accuracy" to location.accuracy.toDouble(),
                        "address" to location.address.orEmpty(),
                        "locationType" to location.locationType,
                    )
                )
            }
        }

        // SDK 万一不回调，这里兜底，避免界面一直转圈。
        val onTimeout = Runnable {
            finish { result.error("timeout", "高德定位超时", null) }
        }
        timeoutTask = onTimeout
        main.postDelayed(onTimeout, timeoutMs)

        client.startLocation()
    }
}
