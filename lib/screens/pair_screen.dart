import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../device_store.dart';

/// First run (or after HR re-pairs or revokes the device): the server address and the pairing code
/// from Time Clock → Devices.
class PairScreen extends StatefulWidget {
  const PairScreen({super.key, this.server, this.notice, required this.onPaired});

  final String? server;
  final String? notice;
  final void Function(KioskApi api, DeviceConfig device) onPaired;

  @override
  State<PairScreen> createState() => _PairScreenState();
}

class _PairScreenState extends State<PairScreen> {
  late final _server = TextEditingController(text: widget.server ?? DeviceStore.defaultServer);
  final _code = TextEditingController();
  final _company = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<String> _deviceInfo() async {
    try {
      final a = await DeviceInfoPlugin().androidInfo;
      return '${a.manufacturer} ${a.model}, Android ${a.version.release}';
    } catch (_) {
      return 'Android';
    }
  }

  Future<void> _pair() async {
    final code = _code.text.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    if (code.length != 8) {
      setState(() => _error = 'The pairing code has 8 letters and numbers');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final server = _server.text.trim();
      final company = _company.text.trim().toLowerCase();
      final paired = await KioskApi(server).pair(code, await _deviceInfo(), company: company.isEmpty ? null : company);
      await DeviceStore.save(server, paired.token);
      widget.onPaired(KioskApi(server, token: paired.token), paired.device);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Couldn\'t reach that server. Check the address.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Icon(Icons.badge_outlined, size: 56, color: theme.colorScheme.primary),
                const SizedBox(height: 12),
                Text('Set up this kiosk', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('In the HRMS portal, open Time Clock → Devices, add this device, and enter the pairing code it shows.',
                    textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                if (widget.notice != null) ...[
                  const SizedBox(height: 16),
                  Card(
                    color: theme.colorScheme.errorContainer,
                    child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.notice!)),
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _code,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 9,
                  style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 6, fontFamily: 'monospace'),
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9-]')), _UpperCase()],
                  decoration: const InputDecoration(labelText: 'Pairing code', hintText: 'ABCD-2345', counterText: '', border: OutlineInputBorder()),
                  onSubmitted: (_) => _pair(),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _company,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Company code (if shown)',
                    helperText: 'Shown with the pairing code when your HRMS serves several companies',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _server,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Server address', border: OutlineInputBorder()),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 16)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _pair,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  child: Text(_busy ? 'Pairing…' : 'Pair', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _UpperCase extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.copyWith(text: newValue.text.toUpperCase());
}
