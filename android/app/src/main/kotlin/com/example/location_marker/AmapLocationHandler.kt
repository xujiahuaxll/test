package com.example.location_marker

import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.security.MessageDigest
import com.amap.api.location.AMapLocation
import com.amap.api.location.AMapLocationClient
import com.amap.api.location.AMapLocationClientOption
import com.amap.api.services.core.AMapException
import com.amap.api.services.core.LatLonPoint
import com.amap.api.services.core.PoiItem
import com.amap.api.services.core.ServiceSettings
import com.amap.api.services.geocoder.GeocodeSearch
import com.amap.api.services.geocoder.RegeocodeAddress
import com.amap.api.services.geocoder.RegeocodeQuery
import com.amap.api.services.geocoder.RegeocodeResult
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

        /** 搜索 SDK 的隐私声明是另一套，单独记。 */
        private var servicePrivacyDeclared = false
    }

    private val main = Handler(Looper.getMainLooper())

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        // 这条不需要 Key：用户正是要拿它去高德后台登记，才能让 Key 生效。
        if (call.method == "appSignature") {
            handleSignature(result)
            return
        }

        val apiKey = call.argument<String>("apiKey").orEmpty()
        if (apiKey.isEmpty()) {
            result.error("no_key", "没有可用的高德 Key", null)
            return
        }
        when (call.method) {
            "locate" -> handleLocate(call, apiKey, result)
            "regeo" -> handleRegeo(call, apiKey, result)
            else -> result.notImplemented()
        }
    }

    private fun handleLocate(
        call: MethodCall,
        apiKey: String,
        result: MethodChannel.Result,
    ) {
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
                        // 这几个才是「某某大厦」这种地点名
                        "poiName" to location.poiName.orEmpty(),
                        "aoiName" to location.aoiName.orEmpty(),
                        "street" to location.street.orEmpty(),
                        "streetNum" to location.streetNum.orEmpty(),
                        "district" to location.district.orEmpty(),
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

    /**
     * 读本安装包的签名 SHA1 与包名。
     *
     * 高德 Key 绑定「包名 + 签名 SHA1」，登记时要填这两个值。以前只能去
     * 构建日志里翻，手机上根本看不到；直接显示在设置页里，换一版包自己
     * 就能核对、改绑，不用回到电脑前。
     */
    private fun handleSignature(result: MethodChannel.Result) {
        try {
            val pm = context.packageManager
            val name = context.packageName
            val certificates: Array<android.content.pm.Signature> =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    val info = pm.getPackageInfo(
                        name,
                        PackageManager.GET_SIGNING_CERTIFICATES,
                    )
                    val signingInfo = info.signingInfo
                    if (signingInfo == null) {
                        result.error("no_signature", "读不到签名信息", null)
                        return
                    }
                    // 轮换过密钥时 apkContentsSigners 给的是当前这本
                    signingInfo.apkContentsSigners
                } else {
                    @Suppress("DEPRECATION")
                    val info = pm.getPackageInfo(
                        name,
                        PackageManager.GET_SIGNATURES,
                    )
                    @Suppress("DEPRECATION")
                    info.signatures
                } ?: emptyArray()

            val first = certificates.firstOrNull()
            if (first == null) {
                result.error("no_signature", "读不到签名信息", null)
                return
            }
            result.success(
                mapOf(
                    "packageName" to name,
                    "sha1" to hexWithColons(sha1Of(first.toByteArray())),
                    "sha256" to hexWithColons(digestOf(first.toByteArray(), "SHA-256")),
                )
            )
        } catch (e: Throwable) {
            result.error("signature_failed", "读取签名失败：${e.message}", null)
        }
    }

    private fun sha1Of(bytes: ByteArray): ByteArray = digestOf(bytes, "SHA-1")

    private fun digestOf(bytes: ByteArray, algorithm: String): ByteArray =
        MessageDigest.getInstance(algorithm).digest(bytes)

    /** 高德后台要的是 AA:BB:CC 这种大写冒号分隔的写法。 */
    private fun hexWithColons(bytes: ByteArray): String =
        bytes.joinToString(":") { "%02X".format(it) }

    /**
     * 逆地理编码：拿坐标换「格式化地址 + 附近 POI 列表」。
     *
     * 定位结果自带的 address 有时是空的（拿到缓存结果、或当时联不上解析
     * 服务），而且它只给一条街道地址。搜索 SDK 这条是独立的一次请求，
     * 还能返回附近的 POI，用户就能像在高德地图里那样挑「某某大厦」。
     *
     * 传进来的是 WGS-84，用 GeocodeSearch.GPS 让高德自己换算，少转一道。
     */
    private fun handleRegeo(
        call: MethodCall,
        apiKey: String,
        result: MethodChannel.Result,
    ) {
        val latitude = call.argument<Double>("latitude")
        val longitude = call.argument<Double>("longitude")
        if (latitude == null || longitude == null) {
            result.error("bad_args", "缺少坐标", null)
            return
        }
        val radius = (call.argument<Int>("radius") ?: 200).toFloat()

        // 搜索 SDK 的 Key 与隐私声明是独立的一套，和地图、定位不共用。
        if (!servicePrivacyDeclared) {
            ServiceSettings.updatePrivacyShow(context, true, true)
            ServiceSettings.updatePrivacyAgree(context, true)
            servicePrivacyDeclared = true
        }
        ServiceSettings.getInstance().setApiKey(apiKey)
        ServiceSettings.getInstance().setLanguage(ServiceSettings.CHINESE)

        val search = try {
            GeocodeSearch(context)
        } catch (e: AMapException) {
            result.error("regeo_init_failed", "逆地理编码初始化失败：${e.errorMessage}", null)
            return
        }

        var replied = false
        search.setOnGeocodeSearchListener(
            object : GeocodeSearch.OnGeocodeSearchListener {
                override fun onRegeocodeSearched(
                    regeocodeResult: RegeocodeResult?,
                    rCode: Int,
                ) {
                    main.post {
                        if (replied) return@post
                        replied = true
                        if (rCode != AMapException.CODE_AMAP_SUCCESS) {
                            // 码必须带上：1002 是 Key 无效，1806 是网络不通，
                            // 处理方式完全不同，只说一句「失败」等于没说。
                            result.error(
                                "regeo_$rCode",
                                "逆地理编码失败（错误码 $rCode）",
                                null,
                            )
                            return@post
                        }
                        val address = regeocodeResult?.regeocodeAddress
                        if (address == null) {
                            result.error("regeo_empty", "逆地理编码没有返回结果", null)
                            return@post
                        }
                        result.success(toMap(address))
                    }
                }

                override fun onGeocodeSearched(
                    geocodeResult: com.amap.api.services.geocoder.GeocodeResult?,
                    rCode: Int,
                ) {
                    // 这里只用逆地理编码，正向的不处理
                }
            }
        )
        search.getFromLocationAsyn(
            RegeocodeQuery(
                LatLonPoint(latitude, longitude),
                radius,
                GeocodeSearch.GPS,
            )
        )
    }

    private fun toMap(address: RegeocodeAddress): Map<String, Any?> {
        val pois: List<PoiItem> = address.pois ?: emptyList()
        return mapOf(
            "formatAddress" to address.formatAddress.orEmpty(),
            "district" to address.district.orEmpty(),
            "township" to address.township.orEmpty(),
            "neighborhood" to address.neighborhood.orEmpty(),
            "building" to address.building.orEmpty(),
            "aoiName" to (address.aois?.firstOrNull()?.aoiName.orEmpty()),
            // 按距离近的排在前面，界面直接照这个顺序给用户选
            "pois" to pois
                .sortedBy { it.distance }
                .take(20)
                .map { poi ->
                    mapOf(
                        "title" to poi.title.orEmpty(),
                        "snippet" to poi.snippet.orEmpty(),
                        "distance" to poi.distance,
                        "typeDes" to poi.typeDes.orEmpty(),
                    )
                },
        )
    }
}
