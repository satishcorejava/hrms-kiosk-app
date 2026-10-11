import 'package:flutter/material.dart';

/// A big number pad for the PIN.
class PinPad extends StatelessWidget {
  const PinPad({super.key, required this.onDigit, required this.onBackspace, required this.onClear});

  final void Function(String digit) onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    Widget key(Widget child, VoidCallback onTap, {bool subtle = false}) => Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            height: 64,
            child: subtle
                ? OutlinedButton(onPressed: onTap, style: OutlinedButton.styleFrom(shape: _shape), child: child)
                : FilledButton.tonal(onPressed: onTap, style: FilledButton.styleFrom(shape: _shape), child: child),
          ),
        );
    Widget digit(String d) => key(Text(d, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)), () => onDigit(d));

    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final row in const [['1', '2', '3'], ['4', '5', '6'], ['7', '8', '9']])
        Row(children: [for (final d in row) Expanded(child: digit(d))]),
      Row(children: [
        Expanded(child: key(const Text('Clear', style: TextStyle(fontSize: 18)), onClear, subtle: true)),
        Expanded(child: digit('0')),
        Expanded(child: key(const Icon(Icons.backspace_outlined), onBackspace, subtle: true)),
      ]),
    ]);
  }

  static final _shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(16));
}
