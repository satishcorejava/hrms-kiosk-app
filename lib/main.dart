import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'api.dart';
import 'device_store.dart';
import 'kiosk_mode.dart';
import 'screens/kiosk_screen.dart';
import 'screens/pair_screen.dart';
import 'widgets/face_scan.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A kiosk: full screen, never sleeps.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WakelockPlus.enable();
  await faceServer.start();
  runApp(const KioskApp());
}

class KioskApp extends StatelessWidget {
  const KioskApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF2E7DFF);
    return MaterialApp(
      title: 'HRMS Kiosk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed), useMaterial3: true),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark), useMaterial3: true),
      home: const _Root(),
    );
  }
}

/// Paired? Show the kiosk; otherwise the pairing screen.
class _Root extends StatefulWidget {
  const _Root();
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  bool _loading = true;
  String? _server;
  String? _notice;
  KioskApi? _api;
  DeviceConfig? _device;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final saved = await DeviceStore.read();
    _server = saved.server;
    if (saved.server != null && saved.token != null) {
      final api = KioskApi(saved.server!, token: saved.token);
      try {
        _device = await api.config();
        _api = api;
      } on UnpairedException catch (e) {
        await DeviceStore.forgetToken();
        _notice = e.message;
      } catch (_) {
        // Offline at start-up: keep trying rather than asking to pair again.
        if (mounted) setState(() => _notice = 'Can\'t reach the server. Retrying…');
        await Future<void>.delayed(const Duration(seconds: 10));
        return _start();
      }
    }
    if (_api != null && await DeviceStore.kioskLock()) {
      try {
        await KioskMode.start();
      } catch (_) {}
    }
    if (mounted) setState(() { _loading = false; if (_api != null) _notice = null; });
  }

  Future<void> _unpaired(String message) async {
    await DeviceStore.forgetToken();
    if (!mounted) return;
    setState(() { _api = null; _device = null; _notice = message; });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            if (_notice != null) Padding(padding: const EdgeInsets.only(top: 16), child: Text(_notice!)),
          ]),
        ),
      );
    }
    if (_api == null || _device == null) {
      return PairScreen(
        server: _server,
        notice: _notice,
        onPaired: (api, device) => setState(() { _api = api; _device = device; _notice = null; }),
      );
    }
    return KioskScreen(api: _api!, device: _device!, onUnpaired: _unpaired);
  }
}
