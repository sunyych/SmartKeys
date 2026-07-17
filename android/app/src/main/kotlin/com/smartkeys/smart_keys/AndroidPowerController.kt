package com.smartkeys.smart_keys

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.view.WindowManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AndroidPowerController(
    private val activity: MainActivity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "smart_keys/power")
    private var receiverRegistered = false

    private val powerReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            channel.invokeMethod("powerStateChanged", isPluggedIn())
        }
    }

    init {
        channel.setMethodCallHandler(this)
        registerReceiver()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isPluggedIn" -> result.success(isPluggedIn())
            "setAppBrightness" -> {
                val brightness = call.argument<Number>("brightness")?.toFloat()
                val attributes = activity.window.attributes
                attributes.screenBrightness = brightness?.coerceIn(0.1f, 1.0f)
                    ?: WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
                activity.window.attributes = attributes
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun onForeground() {
        registerReceiver()
        channel.invokeMethod("powerStateChanged", isPluggedIn())
    }

    fun close() {
        if (receiverRegistered) {
            activity.unregisterReceiver(powerReceiver)
            receiverRegistered = false
        }
        channel.setMethodCallHandler(null)
    }

    private fun registerReceiver() {
        if (receiverRegistered) return
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_POWER_CONNECTED)
            addAction(Intent.ACTION_POWER_DISCONNECTED)
            addAction(Intent.ACTION_BATTERY_CHANGED)
        }
        activity.registerReceiver(powerReceiver, filter)
        receiverRegistered = true
    }

    private fun isPluggedIn(): Boolean {
        val battery = activity.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val plugged = battery?.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) ?: 0
        return plugged != 0
    }
}
