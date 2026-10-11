import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../device_store.dart';
import '../kiosk_mode.dart';
import '../widgets/face_scan.dart';
import '../widgets/pin_pad.dart';

enum _Step { idle, face, pin, person, faceForPin, done }

const _label = {'IN': 'Punch In', 'OUT': 'Punch Out', 'BREAK_START': 'Start Break', 'BREAK_END': 'End Break'};
const _icon = {'IN': Icons.login, 'OUT': Icons.logout, 'BREAK_START': Icons.free_breakfast_outlined, 'BREAK_END': Icons.free_breakfast};

String _time(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

String _hhmm(String? hms) {
  if (hms == null) return '';
  final p = hms.split(':');
  return _time(DateTime(2000, 1, 1, int.parse(p[0]), int.parse(p[1])));
}

const _weekdays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

/// The kiosk itself. Staff identify by face or employee code + PIN, see their day, and punch. The
/// time is always the server's: nothing here lets anyone choose it.
class KioskScreen extends StatefulWidget {
  const KioskScreen({super.key, required this.api, required this.device, required this.onUnpaired});

  final KioskApi api;
  final DeviceConfig device;
  final void Function(String message) onUnpaired;

  @override
  State<KioskScreen> createState() => _KioskScreenState();
}

class _KioskScreenState extends State<KioskScreen> {
  late DeviceConfig _device = widget.device;
  _Step _step = _Step.idle;
  Today? _who;
  FaceEvidence? _face;
  String _code = '';
  String _pin = '';
  String? _pendingType;
  String? _message;
  String? _error;
  bool _busy = false;

  /// Server clock minus this device's, both as India wall-clock time.
  Duration _offset = Duration.zero;
  late Timer _tick;
  Timer? _idle;
  Timer? _sync;
  final _codeField = TextEditingController();

  static DateTime _istNow() => DateTime.now().toUtc().add(const Duration(hours: 5, minutes: 30));

  DateTime get _now => _istNow().add(_offset);

  @override
  void initState() {
    super.initState();
    _setClock(_device.serverTime);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    _sync = Timer.periodic(const Duration(minutes: 5), (_) => _refresh());
  }

  @override
  void dispose() {
    _tick.cancel();
    _idle?.cancel();
    _sync?.cancel();
    _codeField.dispose();
    super.dispose();
  }

  void _setClock(DateTime server) {
    final s = DateTime.utc(server.year, server.month, server.day, server.hour, server.minute, server.second);
    _offset = s.difference(_istNow());
  }

  /// Picks up changes HR made (name, mode), keeps the clock right, and notices a revoked device.
  Future<void> _refresh() async {
    try {
      final d = await widget.api.config();
      if (!mounted) return;
      setState(() { _device = d; _setClock(d.serverTime); });
    } on UnpairedException catch (e) {
      widget.onUnpaired(e.message);
    } catch (_) {/* offline: try again later */}
  }

  // ── flow ──

  void _go(_Step step) {
    setState(() { _step = step; _error = null; });
    _armIdle();
  }

  /// Back to the start when someone walks away.
  void _armIdle() {
    _idle?.cancel();
    final wait = switch (_step) {
      _Step.idle => null,
      _Step.done => const Duration(seconds: 4),
      _Step.person => const Duration(seconds: 25),
      _ => const Duration(seconds: 60),
    };
    if (wait != null) _idle = Timer(wait, _reset);
  }

  void _reset() {
    _codeField.clear();
    setState(() {
      _step = _Step.idle;
      _who = null;
      _face = null;
      _code = '';
      _pin = '';
      _pendingType = null;
      _message = null;
      _error = null;
      _busy = false;
    });
    _idle?.cancel();
  }

  Future<String?> _identifyByFace(FaceEvidence face) async {
    try {
      final t = await widget.api.identifyByFace(face);
      _face = face;
      _who = t;
      _go(_Step.person);
      return null;
    } on UnpairedException catch (e) {
      widget.onUnpaired(e.message);
      return e.message;
    } on ApiException catch (e) {
      _armIdle();
      return e.message;
    }
  }

  Future<void> _identifyByPin() async {
    _code = _codeField.text.trim();
    if (_code.isEmpty || _pin.length < 4) return;
    setState(() { _busy = true; _error = null; });
    try {
      _who = await widget.api.identifyByPin(_code, _pin);
      _go(_Step.person);
    } on UnpairedException catch (e) {
      widget.onUnpaired(e.message);
    } on ApiException catch (e) {
      setState(() { _error = e.message; _pin = ''; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _punch(String type) async {
    final who = _who!;
    // A PIN user who needs a face check looks at the camera first.
    if (_face == null && who.faceRequired) {
      _pendingType = type;
      _go(_Step.faceForPin);
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final t = _face != null
          ? await widget.api.punchByFace(who.employeeId, type, _face!)
          : await widget.api.punchByPin(_code, _pin, type);
      _done(t, type);
    } on UnpairedException catch (e) {
      widget.onUnpaired(e.message);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
      _armIdle();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _punchByPinWithFace(FaceEvidence face) async {
    try {
      final t = await widget.api.punchByPin(_code, _pin, _pendingType!, face: face);
      _done(t, _pendingType!);
      return null;
    } on UnpairedException catch (e) {
      widget.onUnpaired(e.message);
      return e.message;
    } on ApiException catch (e) {
      _armIdle();
      return e.message;
    }
  }

  void _done(Today t, String type) {
    HapticFeedback.mediumImpact();
    final at = t.punches.isNotEmpty ? _time(t.punches.last.time) : _time(_now);
    _who = t;
    _message = '${_label[type]} at $at.\nThank you, ${t.firstName}!';
    _go(_Step.done);
  }

  // ── leaving kiosk mode ──

  Future<void> _admin() async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _ExitPinDialog(api: widget.api));
    if (ok != true || !mounted) return;
    final status = await KioskMode.status();
    final lock = await DeviceStore.kioskLock();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text(_device.name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('${status.deviceOwner ? 'Device owner: full kiosk lock' : 'Screen pinning (set the app as device owner for a full lock)'}'
                '${status.locked ? ' · locked now' : ''}'),
          ),
          SwitchListTile(
            title: const Text('Lock the app on screen'),
            subtitle: const Text('Staff can\'t leave the app without the exit PIN'),
            value: lock,
            onChanged: (on) async {
              await DeviceStore.setKioskLock(on);
              try { on ? await KioskMode.start() : await KioskMode.stop(); } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh),
            title: const Text('Refresh settings from the server'),
            onTap: () { Navigator.pop(ctx); _refresh(); },
          ),
          ListTile(
            leading: Icon(Icons.link_off, color: Theme.of(ctx).colorScheme.error),
            title: const Text('Unpair this device'),
            subtitle: const Text('It stops punching until it\'s paired again with a new code'),
            onTap: () async {
              Navigator.pop(ctx);
              await DeviceStore.forgetToken();
              await DeviceStore.setKioskLock(false);
              try { await KioskMode.stop(); } catch (_) {}
              widget.onUnpaired('This device was unpaired. Get a new code under Time Clock → Devices.');
            },
          ),
        ]),
      ),
    );
  }

  // ── layout ──

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Listener(
          onPointerDown: (_) => _armIdle(),
          child: LayoutBuilder(builder: (context, c) {
            final wide = c.maxWidth >= 840 && c.maxWidth > c.maxHeight;
            final header = _Header(now: _now, device: _device, compact: !wide && _step != _Step.idle, onAdmin: _admin);
            final body = AnimatedSwitcher(duration: const Duration(milliseconds: 200), child: KeyedSubtree(key: ValueKey(_step), child: _body(wide)));
            if (wide) {
              return Row(children: [
                SizedBox(width: c.maxWidth * 0.38, child: Padding(padding: const EdgeInsets.all(32), child: header)),
                const VerticalDivider(width: 1),
                Expanded(child: Padding(padding: const EdgeInsets.all(32), child: body)),
              ]);
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [header, const SizedBox(height: 16), Expanded(child: body)]),
            );
          }),
        ),
      ),
    );
  }

  Widget _body(bool wide) {
    final theme = Theme.of(context);
    switch (_step) {
      case _Step.idle:
        return _Idle(device: _device, onFace: () => _go(_Step.face), onPin: () => _go(_Step.pin));

      case _Step.face:
      case _Step.faceForPin:
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_step == _Step.face ? 'Look at the camera' : '${_label[_pendingType]}: face check',
              textAlign: TextAlign.center, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Expanded(child: FaceScan(onCaptured: _step == _Step.face ? _identifyByFace : _punchByPinWithFace)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _reset, style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)), child: const Text('Cancel')),
        ]);

      case _Step.pin:
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                TextField(
                  controller: _codeField,
                  autofocus: true,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 2),
                  decoration: const InputDecoration(labelText: 'Employee code', border: OutlineInputBorder()),
                  onChanged: (_) => _armIdle(),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(border: Border.all(color: theme.colorScheme.outline), borderRadius: BorderRadius.circular(4)),
                  child: Text(_pin.isEmpty ? 'PIN' : '•' * _pin.length,
                      style: TextStyle(fontSize: 30, letterSpacing: 10, color: _pin.isEmpty ? theme.colorScheme.onSurfaceVariant : null)),
                ),
                const SizedBox(height: 8),
                PinPad(
                  onDigit: (d) => setState(() { if (_pin.length < 6) _pin += d; }),
                  onBackspace: () => setState(() { if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1); }),
                  onClear: () => setState(() => _pin = ''),
                ),
                if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: _ErrorText(_error!)),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _busy || _pin.length < 4 ? null : _identifyByPin,
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
                  child: Text(_busy ? 'Checking…' : 'Continue', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                ),
                TextButton(onPressed: _reset, child: const Text('Cancel')),
              ]),
            ),
          ),
        );

      case _Step.person:
        return _Person(who: _who!, busy: _busy, error: _error, onPunch: _punch, onCancel: _reset);

      case _Step.done:
        return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.check_circle, size: wide ? 120 : 96, color: Colors.green.shade600),
            const SizedBox(height: 16),
            Text(_message ?? '', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        );
    }
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.now, required this.device, required this.compact, required this.onAdmin});

  final DateTime now;
  final DeviceConfig device;
  final bool compact;
  final VoidCallback onAdmin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final clock = '$h:${now.minute.toString().padLeft(2, '0')}';
    // Long-press the clock to reach the manager's menu (needs the exit PIN).
    return GestureDetector(
      onLongPress: onAdmin,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
          Text(clock, style: (compact ? theme.textTheme.headlineMedium : theme.textTheme.displayMedium)
              ?.copyWith(fontWeight: FontWeight.w800, fontFeatures: const [FontFeature.tabularFigures()])),
          const SizedBox(width: 6),
          Text('${now.second.toString().padLeft(2, '0')}  ${now.hour < 12 ? 'AM' : 'PM'}',
              style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ]),
        Text('${_weekdays[now.weekday - 1]}, ${now.day} ${_months[now.month - 1]}', style: theme.textTheme.titleMedium),
        if (!compact) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.storefront_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Flexible(child: Text(device.workLocationName ?? device.name, style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          ]),
        ],
      ]),
    );
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.device, required this.onFace, required this.onPin});

  final DeviceConfig device;
  final VoidCallback onFace;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget big(IconData icon, String title, String subtitle, VoidCallback onTap, {bool primary = true}) => SizedBox(
          height: 120,
          child: (primary ? FilledButton.new : FilledButton.tonal)(
            onPressed: onTap,
            style: FilledButton.styleFrom(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24))),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 48),
              const SizedBox(width: 16),
              Flexible(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                  Text(subtitle, style: const TextStyle(fontSize: 15)),
                ]),
              ),
            ]),
          ),
        );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Punch in or out', textAlign: TextAlign.center, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 24),
          if (device.takesFace) big(Icons.face_retouching_natural, 'Face', 'Look at the camera', onFace),
          if (device.takesFace && device.takesPin) const SizedBox(height: 16),
          if (device.takesPin) big(Icons.dialpad, 'Code & PIN', 'Your employee code and PIN', onPin, primary: !device.takesFace),
        ]),
      ),
    );
  }
}

class _Person extends StatelessWidget {
  const _Person({required this.who, required this.busy, required this.error, required this.onPunch, required this.onCancel});

  final Today who;
  final bool busy;
  final String? error;
  final void Function(String type) onPunch;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstIn = who.punches.where((p) => p.type == 'IN').firstOrNull;
    final out = who.punches.where((p) => p.type == 'OUT').firstOrNull;
    final lines = <String>[
      if (who.shiftName != null) '${who.shiftName}: ${_hhmm(who.shiftStart)} – ${_hhmm(who.shiftEnd)}',
      if (firstIn != null) 'In at ${_time(firstIn.time)}${who.lateMinutes > 0 ? ' · late by ${who.lateMinutes} min' : ''}',
      if (out != null) 'Out at ${_time(out.time)}',
      if (who.onBreak) 'On break',
    ];
    Color colorFor(String a) => a == 'IN' ? Colors.green.shade700 : a == 'OUT' ? theme.colorScheme.error : theme.colorScheme.primary;

    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Hi ${who.firstName}', style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            for (final l in lines) Text(l, style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(height: 24),
            if (who.monthLocked)
              const _Notice('This month is locked for payroll. See your manager.')
            else if (who.nextActions.isEmpty)
              const _Notice('You\'ve punched out for this shift. See you next time!')
            else
              for (final a in who.nextActions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: SizedBox(
                    height: 84,
                    child: (a == 'IN' || a == 'OUT' ? FilledButton.new : FilledButton.tonal)(
                      onPressed: busy ? null : () => onPunch(a),
                      style: FilledButton.styleFrom(
                        backgroundColor: a == 'IN' || a == 'OUT' ? colorFor(a) : null,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      ),
                      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_icon[a], size: 32),
                        const SizedBox(width: 12),
                        Text(busy ? 'Recording…' : _label[a]!, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
                      ]),
                    ),
                  ),
                ),
            if (error != null) _ErrorText(error!),
            const SizedBox(height: 8),
            TextButton(onPressed: onCancel, child: const Text('Not you? Start again', style: TextStyle(fontSize: 16))),
          ]),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(20), child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
      );
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 17, fontWeight: FontWeight.w600));
}

/// The manager's exit PIN, checked by the server.
class _ExitPinDialog extends StatefulWidget {
  const _ExitPinDialog({required this.api});
  final KioskApi api;
  @override
  State<_ExitPinDialog> createState() => _ExitPinDialogState();
}

class _ExitPinDialogState extends State<_ExitPinDialog> {
  String _pin = '';
  String? _error;
  bool _busy = false;

  Future<void> _check() async {
    setState(() { _busy = true; _error = null; });
    try {
      await widget.api.checkExitPin(_pin);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() { _error = e.message; _pin = ''; });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Manager'),
      content: SizedBox(
        width: 340,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Enter the device\'s exit PIN'),
          const SizedBox(height: 12),
          Text(_pin.isEmpty ? ' ' : '•' * _pin.length, style: const TextStyle(fontSize: 30, letterSpacing: 10)),
          if (_error != null) _ErrorText(_error!),
          const SizedBox(height: 8),
          PinPad(
            onDigit: (d) => setState(() { if (_pin.length < 8) _pin += d; }),
            onBackspace: () => setState(() { if (_pin.isNotEmpty) _pin = _pin.substring(0, _pin.length - 1); }),
            onClear: () => setState(() => _pin = ''),
          ),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: _busy || _pin.length < 4 ? null : _check, child: const Text('OK')),
      ],
    );
  }
}
