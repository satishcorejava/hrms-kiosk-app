import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_kiosk/api.dart';

void main() {
  test('the server address is normalised to the API root', () {
    expect(KioskApi.normalise('https://hrms.example.com'), 'https://hrms.example.com/api');
    expect(KioskApi.normalise('https://hrms.example.com/'), 'https://hrms.example.com/api');
    expect(KioskApi.normalise('https://hrms.example.com/api/'), 'https://hrms.example.com/api');
    expect(KioskApi.normalise(' hrms.example.com '), 'https://hrms.example.com/api');
  });

  test('a day is read from the server', () {
    final t = Today.fromJson({
      'employeeId': 7,
      'employeeName': 'Asha Rao',
      'shift': {'name': 'General', 'startTime': '09:00:00', 'endTime': '18:00:00'},
      'punches': [
        {'time': '2026-10-12T09:04:00', 'type': 'IN', 'source': 'KIOSK'},
      ],
      'status': 'PRESENT',
      'lateMinutes': 0,
      'onBreak': false,
      'nextActions': ['OUT'],
      'monthLocked': false,
      'faceRequired': true,
    });
    expect(t.firstName, 'Asha');
    expect(t.nextActions, ['OUT']);
    expect(t.punches.single.time.hour, 9);
    expect(t.faceRequired, isTrue);
  });

  test('a break in progress is read with its start and the allowance', () {
    final t = Today.fromJson({
      'employeeId': 7,
      'employeeName': 'Asha Rao',
      'punches': [
        {'time': '2026-10-12T09:00:00', 'type': 'IN', 'source': 'KIOSK'},
        {'time': '2026-10-12T13:00:00', 'type': 'BREAK_START', 'source': 'KIOSK'},
      ],
      'lateMinutes': 0,
      'onBreak': true,
      'nextActions': ['BREAK_END', 'OUT'],
      'monthLocked': false,
      'faceRequired': false,
      'breakMinutes': 52,
      'breakAllowedMinutes': 45,
      'breakStartedAt': '2026-10-12T13:00:00',
    });
    expect(t.onBreak, isTrue);
    expect(t.breakMinutes, 52);
    expect(t.breakAllowedMinutes, 45);
    expect(t.breakStartedAt, DateTime(2026, 10, 12, 13));
  });

  test('a day from an older server, without break details, still reads', () {
    final t = Today.fromJson({
      'employeeId': 7, 'employeeName': 'Asha Rao', 'punches': [], 'lateMinutes': 0, 'onBreak': false,
      'nextActions': ['IN'], 'monthLocked': false, 'faceRequired': false,
    });
    expect(t.breakAllowedMinutes, 0);
    expect(t.breakStartedAt, isNull);
  });
}
