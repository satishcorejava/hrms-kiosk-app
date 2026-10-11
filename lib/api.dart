import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// A refusal from the server, in words for the person at the kiosk.
class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  @override
  String toString() => message;
}

/// The device key is unknown or revoked: back to pairing.
class UnpairedException extends ApiException {
  UnpairedException(super.message) : super(status: 401);
}

class DeviceConfig {
  DeviceConfig({required this.id, required this.name, required this.mode, this.workLocationName, required this.serverTime});
  final int id;
  final String name;
  /// FACE_AND_PIN | FACE | PIN
  final String mode;
  final String? workLocationName;
  final DateTime serverTime;

  bool get takesFace => mode != 'PIN';
  bool get takesPin => mode != 'FACE';

  factory DeviceConfig.fromJson(Map<String, dynamic> j) => DeviceConfig(
        id: (j['id'] as num).toInt(),
        name: j['name'] as String,
        mode: j['mode'] as String,
        workLocationName: j['workLocationName'] as String?,
        serverTime: DateTime.parse(j['serverTime'] as String),
      );
}

class Punch {
  Punch({required this.time, required this.type, required this.source});
  final DateTime time;
  final String type;
  final String source;
  factory Punch.fromJson(Map<String, dynamic> j) =>
      Punch(time: DateTime.parse(j['time'] as String), type: j['type'] as String, source: j['source'] as String);
}

/// Where someone's day stands, and what they can do next.
class Today {
  Today({
    required this.employeeId,
    required this.employeeName,
    this.shiftName,
    this.shiftStart,
    this.shiftEnd,
    required this.punches,
    this.status,
    this.workedMinutes,
    required this.lateMinutes,
    required this.onBreak,
    required this.nextActions,
    required this.monthLocked,
    required this.faceRequired,
  });

  final int employeeId;
  final String employeeName;
  final String? shiftName;
  final String? shiftStart;
  final String? shiftEnd;
  final List<Punch> punches;
  final String? status;
  final int? workedMinutes;
  final int lateMinutes;
  final bool onBreak;
  final List<String> nextActions;
  final bool monthLocked;
  final bool faceRequired;

  String get firstName => employeeName.split(' ').first;

  factory Today.fromJson(Map<String, dynamic> j) {
    final shift = j['shift'] as Map<String, dynamic>?;
    return Today(
      employeeId: (j['employeeId'] as num).toInt(),
      employeeName: j['employeeName'] as String,
      shiftName: shift?['name'] as String?,
      shiftStart: shift?['startTime'] as String?,
      shiftEnd: shift?['endTime'] as String?,
      punches: ((j['punches'] as List?) ?? []).map((p) => Punch.fromJson(p as Map<String, dynamic>)).toList(),
      status: j['status'] as String?,
      workedMinutes: (j['workedMinutes'] as num?)?.toInt(),
      lateMinutes: ((j['lateMinutes'] as num?) ?? 0).toInt(),
      onBreak: j['onBreak'] == true,
      nextActions: ((j['nextActions'] as List?) ?? []).cast<String>(),
      monthLocked: j['monthLocked'] == true,
      faceRequired: j['faceRequired'] == true,
    );
  }
}

/// A face capture from the face page: what the server compares, and the photo it keeps.
class FaceEvidence {
  FaceEvidence(this.descriptor, this.photo);
  final List<double> descriptor;
  final String photo;
  Map<String, dynamic> toJson() => {'descriptor': descriptor, 'photo': photo};
}

/// The HRMS backend's /api/device endpoints.
class KioskApi {
  KioskApi(String baseUrl, {this.token}) : baseUrl = normalise(baseUrl);

  final String baseUrl;
  final String? token;

  /// "https://host", "https://host/", "https://host/api" -> "https://host/api"
  static String normalise(String url) {
    var u = url.trim().replaceAll(RegExp(r'/+$'), '');
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
    if (!u.toLowerCase().endsWith('/api')) u = '$u/api';
    return u;
  }

  Future<Map<String, dynamic>?> _call(String method, String path, [Object? body, String? tenant]) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = {'Content-Type': 'application/json', 'Accept': 'application/json', 'X-Device-Token': ?token, 'X-Tenant': ?tenant};
    http.Response res;
    try {
      final f = method == 'GET' ? http.get(uri, headers: headers) : http.post(uri, headers: headers, body: jsonEncode(body ?? {}));
      res = await f.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException('The server is taking too long. Check the internet connection and try again.');
    } on SocketException {
      throw ApiException('No connection. Check the Wi-Fi or mobile data.');
    } on http.ClientException {
      throw ApiException('No connection. Check the Wi-Fi or mobile data.');
    }
    Map<String, dynamic>? json;
    try {
      json = res.body.isEmpty ? null : jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json?['data'] as Map<String, dynamic>?;
    final message = (json?['error'] ?? json?['message'] ?? 'Something went wrong (${res.statusCode})').toString();
    if (res.statusCode == 401 && token != null) throw UnpairedException(message);
    throw ApiException(message, status: res.statusCode);
  }

  /// [company] is the company code from Time Clock → Devices when HRMS serves several companies;
  /// the key that comes back carries it, so later calls need nothing more.
  Future<({String token, DeviceConfig device})> pair(String code, String deviceInfo, {String? company}) async {
    final d = await _call('POST', '/device/pair', {'code': code, 'deviceInfo': deviceInfo}, company);
    return (token: d!['token'] as String, device: DeviceConfig.fromJson(d['device'] as Map<String, dynamic>));
  }

  Future<DeviceConfig> config() async => DeviceConfig.fromJson((await _call('GET', '/device/config'))!);

  Future<Today> identifyByPin(String employeeCode, String pin) async =>
      Today.fromJson((await _call('POST', '/device/identify/pin', {'employeeCode': employeeCode, 'pin': pin}))!);

  Future<Today> identifyByFace(FaceEvidence face) async => Today.fromJson((await _call('POST', '/device/identify/face', face.toJson()))!);

  Future<Today> punchByPin(String employeeCode, String pin, String type, {FaceEvidence? face}) async => Today.fromJson(
      (await _call('POST', '/device/punch/pin', {'employeeCode': employeeCode, 'pin': pin, 'type': type, ...?face?.toJson()}))!);

  Future<Today> punchByFace(int employeeId, String type, FaceEvidence face) async =>
      Today.fromJson((await _call('POST', '/device/punch/face', {'employeeId': employeeId, 'type': type, ...face.toJson()}))!);

  Future<void> checkExitPin(String pin) async => _call('POST', '/device/exit', {'pin': pin});
}
