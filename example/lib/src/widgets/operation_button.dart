import 'package:flutter/material.dart';

class OperationButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool enabled;
  final VoidCallback? onPressed;
  final ButtonStyle? style;

  const OperationButton({
    super.key,
    required this.label,
    required this.icon,
    this.enabled = true,
    this.onPressed,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Text(label),
          onPressed: enabled ? onPressed : null,
          style: style,
        ),
      ),
    );
  }
}
