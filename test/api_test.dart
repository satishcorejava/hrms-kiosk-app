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
}
