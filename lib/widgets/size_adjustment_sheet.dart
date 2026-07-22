import 'package:flutter/material.dart';

Future<void> showMannequinSizeSheet({
  required BuildContext context,
  required double initialWidth,
  required double initialHeight,
  required ValueChanged<double> onWidthChanged,
  required ValueChanged<double> onHeightChanged,
  required VoidCallback onReset,
}) {
  var width = initialWidth;
  var height = initialHeight;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Căn kích thước người nộm',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Dùng hai thanh này để kéo người nộm khớp với người bên ngoài.',
                  ),
                  const SizedBox(height: 18),
                  _ScaleSlider(
                    icon: Icons.height,
                    label: 'Chiều cao',
                    value: height,
                    onChanged: (value) {
                      setModalState(() => height = value);
                      onHeightChanged(value);
                    },
                  ),
                  _ScaleSlider(
                    icon: Icons.width_normal,
                    label: 'Chiều rộng',
                    value: width,
                    onChanged: (value) {
                      setModalState(() => width = value);
                      onWidthChanged(value);
                    },
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () {
                      setModalState(() {
                        width = 1;
                        height = 1;
                      });
                      onReset();
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Đặt lại 100%'),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        SizedBox(width: 88, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            min: 0.65,
            max: 1.45,
            divisions: 32,
            label: '${(value * 100).round()}%',
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 52,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
