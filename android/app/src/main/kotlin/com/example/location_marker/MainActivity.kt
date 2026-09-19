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
    }
}
