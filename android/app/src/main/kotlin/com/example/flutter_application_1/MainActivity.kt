package com.example.flutter_application_1

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val appLifecycleChannel = "smart_ambulance/app_lifecycle"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appLifecycleChannel)
            .setMethodCallHandler { call, result ->
                if (call.method == "moveTaskToBack") {
                    moveTaskToBack(true)
                    result.success(true)
                } else {
                    result.notImplemented()
                }
            }
    }
}
