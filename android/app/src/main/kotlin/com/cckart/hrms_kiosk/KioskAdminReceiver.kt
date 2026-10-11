package com.cckart.hrms_kiosk

import android.app.admin.DeviceAdminReceiver

/**
 * Needed for device-owner kiosk mode:
 *   adb shell dpm set-device-owner com.cckart.hrms_kiosk/.KioskAdminReceiver
 * Then the app can lock itself on screen with no prompt and no way out except the exit PIN.
 */
class KioskAdminReceiver : DeviceAdminReceiver()
