import 'package:flutter/material.dart';
import '../theme.dart';

class AtRedButton extends StatelessWidget {
  const AtRedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 18, vertical: 12);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[
          Icon(icon, size: 16),
          const SizedBox(width: 8),
        ],
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      ],
    );
    if (outlined) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AtShieldColors.accent,
          side: const BorderSide(color: AtShieldColors.accent),
          padding: pad,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        child: child,
      );
    }
    return FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: AtShieldColors.accent,
        foregroundColor: Colors.white,
        padding: pad,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: child,
    );
  }
}
