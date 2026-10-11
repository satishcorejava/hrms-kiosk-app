import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The server address and device key, kept in Android's encrypted storage.
class DeviceStore {
  static const _storage = FlutterSecureStorage();
  static const _server = 'server';
  static const _token = 'token';
  static const _lock = 'kiosk_lock';

  static const defaultServer = 'https://hrms-backend-production-9ce1.up.railway.app';

  static Future<({String? server, String? token})> read() async =>
      (server: await _storage.read(key: _server), token: await _storage.read(key: _token));

  static Future<void> save(String server, String token) async {
    await _storage.write(key: _server, value: server);
    await _storage.write(key: _token, value: token);
  }

  /// Keeps the server address, so pairing again only needs a new code.
  static Future<void> forgetToken() => _storage.delete(key: _token);

  /// Whether to lock the app on screen when it starts.
  static Future<bool> kioskLock() async => (await _storage.read(key: _lock)) == 'true';

  static Future<void> setKioskLock(bool on) => _storage.write(key: _lock, value: on.toString());
}
