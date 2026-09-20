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
import com.amap.api.services.district.DistrictItem
import com.amap.api.services.district.DistrictResult
import com.amap.api.services.district.DistrictSearch
import com.amap.api.services.district.DistrictSearchQuery
import com.amap.api.services.geocoder.GeocodeSearch
import com.amap.api.services.geocoder.RegeocodeAddress
import com.amap.api.services.geocoder.RegeocodeQuery
import com.amap.api.services.geocoder.RegeocodeResult
import com.amap.api.services.help.Inputtips
import com.amap.api.services.help.InputtipsQuery
import com.amap.api.services.help.Tip
import com.amap.api.services.poisearch.PoiResult
import com.amap.api.services.poisearch.PoiSearch
import com.amap.api.services.poisearch.SubPoiItem
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
            "inputTips" -> handleInputTips(call, apiKey, result)
            "nearbyPois" -> handleNearbyPois(call, apiKey, result)
            "districts" -> handleDistricts(call, apiKey, result)
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
                        // 手动选点页要拿它做搜索的城市范围
                        "province" to location.province.orEmpty(),
                        "city" to location.city.orEmpty(),
                        "cityCode" to location.cityCode.orEmpty(),
                        "adCode" to location.adCode.orEmpty(),
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
        // 调用方说清楚传的是哪种坐标：地图拖点本来就是 GCJ-02，
        // 先转成 WGS-84 再让高德转回去，纯属多绕一道、白添误差。
        val gcj = call.argument<Boolean>("gcj") ?: false

        // 搜索 SDK 的 Key 与隐私声明是独立的一套，和地图、定位不共用。
        prepareServices(apiKey)

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
        val query = RegeocodeQuery(
            LatLonPoint(latitude, longitude),
            radius,
            if (gcj) GeocodeSearch.AMAP else GeocodeSearch.GPS,
        )
        // 默认是 base，只回一条街道地址，不带 POI 和 AOI——
        // 「附近地点」一直是空的就是因为这个，必须显式要 all。
        query.setExtensions(GeocodeSearch.EXTENSIONS_ALL)
        search.getFromLocationAsyn(query)
    }

    /** POI 一律带上 GCJ-02 坐标，界面选中后要把图钉挪过去。 */
    private fun poiToMap(poi: PoiItem): Map<String, Any?> = mapOf(
        "title" to poi.title.orEmpty(),
        "snippet" to poi.snippet.orEmpty(),
        "distance" to poi.distance,
        "typeDes" to poi.typeDes.orEmpty(),
        // 六位分类编码。Dart 侧靠它把「楼宇、地铁站」排到「咖啡店」前面——
        // 高德的 poiweight 权重值 SDK 不暴露，只能用公开的分类自己估。
        "typeCode" to poi.typeCode.orEmpty(),
        "latitude" to poi.latLonPoint?.latitude,
        "longitude" to poi.latLonPoint?.longitude,
    )

    /**
     * 子 POI 摊平成独立条目，「某某地铁站B口」就是这么来的。
     *
     * SubPoiItem 没有自己的 typeCode，继承父级的——出入口本来就属于
     * 父站点那一类，不继承的话它会掉进「未知分类」，排不到店铺前面。
     */
    private fun subPoiToMap(parent: PoiItem, sub: SubPoiItem): Map<String, Any?> {
        val ownTitle = sub.title.orEmpty().trim()
        val subName = sub.subName.orEmpty().trim()
        return mapOf(
            // getTitle 通常已经是全名；只有它为空时才拿父名拼一个
            "title" to if (ownTitle.isNotEmpty()) ownTitle
                       else (parent.title.orEmpty() + subName),
            "snippet" to sub.snippet.orEmpty(),
            "distance" to sub.distance,
            "typeDes" to sub.subTypeDes.orEmpty(),
            "typeCode" to parent.typeCode.orEmpty(),
            "latitude" to sub.latLonPoint?.latitude,
            "longitude" to sub.latLonPoint?.longitude,
        )
    }

    /**
     * 输入提示：边打字边给候选，和地图 App 里的搜索一样。
     *
     * 带上当前位置做偏置，同城同名的地点会把近的排前面。
     */
    private fun handleInputTips(
        call: MethodCall,
        apiKey: String,
        result: MethodChannel.Result,
    ) {
        val keyword = call.argument<String>("keyword").orEmpty().trim()
        if (keyword.isEmpty()) {
            result.success(emptyList<Map<String, Any?>>())
            return
        }
        prepareServices(apiKey)

        val query = InputtipsQuery(keyword, call.argument<String>("city").orEmpty())
        // 由调用方决定限不限城市。不限的话搜「人民医院」会把全国的都列出来，
        // 翻十页也找不到身边那家；选了城市就只在城里找。
        query.cityLimit = call.argument<Boolean>("cityLimit") ?: false
        val lat = call.argument<Double>("latitude")
        val lng = call.argument<Double>("longitude")
        if (lat != null && lng != null) {
            query.location = LatLonPoint(lat, lng)
        }

        var replied = false
        val tips = Inputtips(context, query)
        tips.setInputtipsListener { list: List<Tip>?, rCode: Int ->
            main.post {
                if (replied) return@post
                replied = true
                if (rCode != AMapException.CODE_AMAP_SUCCESS) {
                    result.error("tips_$rCode", "搜索失败（错误码 $rCode）", null)
                    return@post
                }
                result.success(
                    (list ?: emptyList())
                        // 公交线路之类的提示没有坐标，留着也跳不过去
                        .filter { it.point != null && !it.name.isNullOrBlank() }
                        .map { tip ->
                            mapOf(
                                "title" to tip.name.orEmpty(),
                                "district" to tip.district.orEmpty(),
                                "snippet" to tip.address.orEmpty(),
                                "latitude" to tip.point.latitude,
                                "longitude" to tip.point.longitude,
                            )
                        }
                )
            }
        }
        tips.requestInputtipsAsyn()
    }

    /**
     * 周边搜索：拖到哪就列出附近有哪些地方，按距离排。
     *
     * 比逆地理编码自带的那份 POI 列表准得多，「XX号楼」这种也搜得到——
     * 之前拖到 27 号楼却显示成一百多米外的公寓，就是因为只用了前者。
     */
    private fun handleNearbyPois(
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
        val radius = call.argument<Int>("radius") ?: 1000
        prepareServices(apiKey)

        val query = PoiSearch.Query(
            call.argument<String>("keyword").orEmpty(),
            // 分类限定。留空就是不限，由 Dart 侧按分类权重自己重排
            call.argument<String>("types").orEmpty(),
            "",
        )
        query.pageSize = 25
        query.pageNum = 0
        // 这里刻意不开 distanceSort：开了就是纯距离排序，等于把高德自己的
        // POI 权重扔掉——而商户密度远高于楼宇，结果就是拖到哪儿都是「XX咖啡」。
        // 关掉它走高德的默认排序，权重高的（楼宇、地铁站）先回来，
        // Dart 侧再按分类权重和距离细排一次。
        query.setDistanceSort(false)
        // 要子 POI，地铁站的各个出入口才会跟着父站点一起回来
        query.requireSubPois(true)
        query.setExtensions(PoiSearch.EXTENSIONS_ALL)

        val search = try {
            PoiSearch(context, query)
        } catch (e: AMapException) {
            result.error("poi_init_failed", "周边搜索初始化失败：${e.errorMessage}", null)
            return
        }
        // 这里收的是 GCJ-02，和地图同一套坐标
        search.setBound(
            PoiSearch.SearchBound(LatLonPoint(latitude, longitude), radius),
        )

        var replied = false
        search.setOnPoiSearchListener(
            object : PoiSearch.OnPoiSearchListener {
                override fun onPoiSearched(poiResult: PoiResult?, rCode: Int) {
                    main.post {
                        if (replied) return@post
                        replied = true
                        if (rCode != AMapException.CODE_AMAP_SUCCESS) {
                            result.error(
                                "poi_$rCode",
                                "周边搜索失败（错误码 $rCode）",
                                null,
                            )
                            return@post
                        }
                        val pois = (poiResult?.pois ?: arrayListOf())
                            .filter { !it.title.isNullOrBlank() }
                        result.success(
                            pois.flatMap { poi ->
                                // 父站点和它的出入口都列出来，让用户自己挑
                                listOf(poiToMap(poi)) +
                                    (poi.getSubPois() ?: emptyList())
                                        .filter { !it.title.isNullOrBlank() }
                                        .map { subPoiToMap(poi, it) }
                            }
                        )
                    }
                }

                override fun onPoiItemSearched(item: PoiItem?, rCode: Int) {
                    // 只用周边搜索，单个 POI 详情不处理
                }
            }
        )
        search.searchPOIAsyn()
    }

    /**
     * 行政区划查询：给手动选点页的城市选择器供货。
     *
     * 城市名单不写死在代码里——写死就意味着行政区划一调整就得重新发包，
     * 而且漏掉哪个城市用户只能干等。直接问高德，它本来就维护着这份数据。
     *
     * [subDistrict] 是往下取几级：查「中国」取 2 级就是「省 + 市」，
     * 一次请求把整棵选择树拿全，之后翻省份、搜城市都在本地做。
     */
    private fun handleDistricts(
        call: MethodCall,
        apiKey: String,
        result: MethodChannel.Result,
    ) {
        val keyword = call.argument<String>("keyword").orEmpty().trim()
        val level = call.argument<String>("level").orEmpty().trim()
        val subDistrict = call.argument<Int>("subDistrict") ?: 1
        prepareServices(apiKey)

        val search = try {
            DistrictSearch(context)
        } catch (e: AMapException) {
            result.error(
                "district_init_failed",
                "行政区划查询初始化失败：${e.errorMessage}",
                null,
            )
            return
        }

        val query = DistrictSearchQuery()
        query.keywords = keyword.ifEmpty { DistrictSearchQuery.KEYWORDS_COUNTRY }
        if (level.isNotEmpty()) query.keywordsLevel = level
        // 边界是一大串经纬度点，这里只要名字，不要白传几百 KB
        query.isShowBoundary = false
        query.isShowChild = true
        query.subDistrict = subDistrict
        query.pageSize = 20
        query.pageNum = 0
        search.setQuery(query)

        var replied = false
        search.setOnDistrictSearchListener { districtResult: DistrictResult? ->
            main.post {
                if (replied) return@post
                replied = true
                // 这个回调没有 rCode，错误藏在结果对象里
                val failure = districtResult?.getAMapException()
                if (failure != null &&
                    failure.errorCode != AMapException.CODE_AMAP_SUCCESS
                ) {
                    result.error(
                        "district_${failure.errorCode}",
                        "行政区划查询失败（错误码 ${failure.errorCode}）",
                        null,
                    )
                    return@post
                }
                val items = districtResult?.getDistrict() ?: arrayListOf()
                result.success(items.map { districtToMap(it) })
            }
        }
        search.searchDistrictAsyn()
    }

    /** 递归展开子级，Dart 侧直接拿去建两级列表。 */
    private fun districtToMap(item: DistrictItem): Map<String, Any?> = mapOf(
        "name" to item.name.orEmpty(),
        "adcode" to item.adcode.orEmpty(),
        "citycode" to item.citycode.orEmpty(),
        "level" to item.level.orEmpty(),
        "latitude" to item.center?.latitude,
        "longitude" to item.center?.longitude,
        "children" to (item.getSubDistrict() ?: emptyList())
            .map { districtToMap(it) },
    )

    /** 搜索类接口共用的 Key 与隐私声明准备。 */
    private fun prepareServices(apiKey: String) {
        if (!servicePrivacyDeclared) {
            ServiceSettings.updatePrivacyShow(context, true, true)
            ServiceSettings.updatePrivacyAgree(context, true)
            servicePrivacyDeclared = true
        }
        ServiceSettings.getInstance().setApiKey(apiKey)
        ServiceSettings.getInstance().setLanguage(ServiceSettings.CHINESE)
    }

    private fun toMap(address: RegeocodeAddress): Map<String, Any?> {
        val pois: List<PoiItem> = address.pois ?: emptyList()
        val aoi = address.aois?.firstOrNull()
        return mapOf(
            "formatAddress" to address.formatAddress.orEmpty(),
            "province" to address.province.orEmpty(),
            "city" to address.city.orEmpty(),
            "cityCode" to address.cityCode.orEmpty(),
            // 直辖市的 city 是空的，adCode 前四位才是能用来限定搜索的城市码
            "adCode" to address.adCode.orEmpty(),
            "district" to address.district.orEmpty(),
            "township" to address.township.orEmpty(),
            "neighborhood" to address.neighborhood.orEmpty(),
            "building" to address.building.orEmpty(),
            "aoiName" to aoi?.aoiName.orEmpty(),
            // AOI 的面积（平方米）。大学城、开发区整片也是一个 AOI，
            // 拿它当地点名等于什么都没说，Dart 侧靠这个数把太大的滤掉。
            "aoiArea" to aoi?.aoiArea?.toDouble(),
            "aoiDistance" to aoi?.distance?.toDouble(),
            // 保持高德给的顺序，不要按距离重排：它自己的排序带 POI 权重，
            // 按距离排等于把权重扔了，再截前 20 条就可能把落点所在的那栋楼
            // 切掉——先排到第 21 位，永远轮不上。细排交给 Dart 的
            // PlaceRanking，那边看得到分类编码。
            "pois" to pois.take(20).map { poi -> poiToMap(poi) },
        )
    }
}
