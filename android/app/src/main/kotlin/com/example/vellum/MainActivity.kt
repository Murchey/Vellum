package com.example.vellum

import android.content.Context
import android.os.BatteryManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "vellum/device")
            .setMethodCallHandler { call, result ->
                if (call.method != "batteryLevel") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val batteryManager = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
                val level = batteryManager.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
                if (level >= 0) result.success(level) else result.error("UNAVAILABLE", "Battery level unavailable", null)
            }
    }
}
