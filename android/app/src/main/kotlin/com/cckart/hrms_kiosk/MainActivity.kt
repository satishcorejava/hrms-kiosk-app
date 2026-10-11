package com.cckart.hrms_kiosk

import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.content.Context
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Kiosk mode for the Flutter side ("hrms_kiosk/kiosk"):
 *  - start: lock the app on screen. As device owner it's silent and complete; otherwise Android's
 *    screen pinning asks once and can be undone by holding Back + Overview.
 *  - stop: unlock (after the exit PIN, checked by the server).
 */
class MainActivity : FlutterActivity() {

    private val channel = "hrms_kiosk/kiosk"

    private fun admin() = ComponentName(this, KioskAdminReceiver::class.java)

    private fun dpm() = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager

    private fun isDeviceOwner() = dpm().isDeviceOwnerApp(packageName)

    private fun inLockTask(): Boolean {
        val am = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) am.lockTaskModeState != ActivityManager.LOCK_TASK_MODE_NONE
        else @Suppress("DEPRECATION") am.isInLockTaskMode
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "start" -> {
                        if (isDeviceOwner()) dpm().setLockTaskPackages(admin(), arrayOf(packageName))
                        if (!inLockTask()) startLockTask()
                        result.success(true)
                    }
                    "stop" -> {
                        if (inLockTask()) stopLockTask()
                        result.success(true)
                    }
                    "status" -> result.success(mapOf("locked" to inLockTask(), "deviceOwner" to isDeviceOwner()))
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("kiosk", e.message, null)
            }
        }
    }
}
