package com.example.location_marker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = AmapLocationHandler(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            AmapLocationHandler.CHANNEL,
        ).setMethodCallHandler { call, result -> handler.handle(call, result) }

        // 安装器要的是 Activity 而不是 application context：后者启动
        // Activity 得加 NEW_TASK，安装界面会跑到别的任务栈，装完退回来
        // 看到的不是本应用。
        val installer = InstallerHandler(this)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            InstallerHandler.CHANNEL,
        ).setMethodCallHandler { call, result -> installer.handle(call, result) }
    }
}
