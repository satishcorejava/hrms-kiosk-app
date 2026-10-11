import 'package:flutter/services.dart';

/// Locks the app on screen (Android lock task). Silent and complete when the app is device owner;
/// otherwise Android's screen pinning, which asks once.
class KioskMode {
  static const _channel = MethodChannel('hrms_kiosk/kiosk');

  static Future<void> start() => _channel.invokeMethod('start');

  static Future<void> stop() => _channel.invokeMethod('stop');

  static Future<({bool locked, bool deviceOwner})> status() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('status');
      return (locked: m?['locked'] == true, deviceOwner: m?['deviceOwner'] == true);
    } catch (_) {
      return (locked: false, deviceOwner: false);
    }
  }
}
