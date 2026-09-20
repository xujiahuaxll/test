package com.example.location_marker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * 把下载好的 APK 交给系统安装器。
 *
 * 需要 Activity 而不是 ApplicationContext：从 application context 启动
 * Activity 得加 FLAG_ACTIVITY_NEW_TASK，安装界面会跑到另一个任务栈里，
 * 装完退回来看到的不是本应用。所以这里拿当前 Activity。
 */
class InstallerHandler(private val activity: Activity) {

    companion object {
        const val CHANNEL = "location_marker/installer"

        /** 和 AndroidManifest 里 provider 的 authorities 必须一致。 */
        private const val AUTHORITY = "com.example.location_marker.fileprovider"

        private const val APK_MIME = "application/vnd.android.package-archive"
    }

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "installApk" -> installApk(call, result)
            "canInstall" -> result.success(canRequestInstall())
            else -> result.notImplemented()
        }
    }

    /**
     * Android 8 起，安装未知来源的包要用户单独给本应用授权。
     * 8 以下没有这道开关，直接放行。
     */
    private fun canRequestInstall(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return activity.packageManager.canRequestPackageInstalls()
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path").orEmpty()
        if (path.isEmpty()) {
            result.error("bad_args", "缺少 APK 路径", null)
            return
        }
        val apk = File(path)
        if (!apk.exists()) {
            result.error("not_found", "安装包不存在：$path", null)
            return
        }

        // 没授权就把人送到那个设置页。直接调安装会静默什么都不发生，
        // 用户只会以为按钮坏了。
        if (!canRequestInstall()) {
            try {
                activity.startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${activity.packageName}"),
                    )
                )
            } catch (e: Exception) {
                // 个别定制系统没有这个设置页，退回应用详情页
                activity.startActivity(
                    Intent(
                        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                        Uri.parse("package:${activity.packageName}"),
                    )
                )
            }
            result.success("needPermission")
            return
        }

        try {
            // 直接给 file:// 会在 Android 7+ 抛 FileUriExposedException，
            // 必须走 FileProvider 换一个 content:// 并临时授读权限。
            val uri: Uri = FileProvider.getUriForFile(activity, AUTHORITY, apk)
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, APK_MIME)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivity(intent)
            result.success("started")
        } catch (e: Exception) {
            result.error("install_failed", "唤起安装失败：${e.message}", null)
        }
    }
}
