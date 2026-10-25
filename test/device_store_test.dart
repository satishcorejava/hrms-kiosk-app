import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_kiosk/api.dart';
import 'package:hrms_kiosk/device_store.dart';

void main() {
  test('new kiosks pair with the gateway, which reaches the HRMS API', () {
    expect(DeviceStore.defaultServer, 'https://api.cckart.com/hrms');
    expect(KioskApi.normalise(DeviceStore.defaultServer), 'https://api.cckart.com/hrms/api');
  });

  test('a kiosk paired with the retired address moves to the gateway; others stay put', () {
    expect(DeviceStore.current('https://hrms-backend-production-9ce1.up.railway.app'), DeviceStore.defaultServer);
    expect(DeviceStore.current('https://hrms-backend-production-9ce1.up.railway.app/api/'), DeviceStore.defaultServer);
    expect(DeviceStore.current('https://hrms.example.com'), 'https://hrms.example.com');
    expect(DeviceStore.current('https://api.cckart.com/hrms'), 'https://api.cckart.com/hrms');
  });
}
