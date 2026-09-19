import 'package:flutter/material.dart';
import '../theme.dart';

class AtRedButton extends StatefulWidget {
  const AtRedButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.ghost = false,
    this.icon,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool ghost;
  final IconData? icon;
  final bool dense;

  @override
  State<AtRedButton> createState() => _AtRedButtonState();
}

class _AtRedButtonState extends State<AtRedButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final dense = widget.dense;
    final ghost = widget.ghost;
    final outlined = widget.outlined;
    final onPressed = widget.onPressed;
    final pad = dense
        ? const EdgeInsets.symmetric(horizontal: 14, vertical: 10)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 11);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.icon != null) ...[
          Icon(widget.icon, size: 16),
          const SizedBox(width: 8),
        ],
        Text(
          widget.label,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            letterSpacing: 0.02,
            fontSize: 13,
          ),
        ),
      ],
    );

    final reduce = MediaQuery.disableAnimationsOf(context);
    final Widget button;

    if (ghost || outlined) {
      button = OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: AtShieldColors.text,
          side: const BorderSide(color: AtShieldColors.border),
          padding: pad,
          minimumSize: const Size(0, 36),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
          ),
        ).copyWith(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (ghost && states.contains(WidgetState.hovered)) {
              return AtShieldColors.danger;
            }
            return ghost ? AtShieldColors.text : AtShieldColors.accent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (ghost && states.contains(WidgetState.hovered)) {
              return BorderSide(
                color: AtShieldColors.danger.withValues(alpha: 0.55),
              );
            }
            return BorderSide(
              color: ghost ? AtShieldColors.border : AtShieldColors.accent,
            );
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (ghost && states.contains(WidgetState.hovered)) {
              return AtShieldColors.danger.withValues(alpha: 0.08);
            }
            return Colors.transparent;
          }),
        ),
        child: child,
      );
    } else {
      button = FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AtShieldColors.accent,
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              AtShieldColors.accent.withValues(alpha: 0.35),
          padding: pad,
          minimumSize: const Size(0, 36),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
          ),
        ),
        child: child,
      );
    }

    return Listener(
      onPointerDown:
          onPressed == null ? null : (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed && !reduce ? 0.985 : 1,
        duration:
            reduce ? Duration.zero : const Duration(milliseconds: 80),
        curve: const Cubic(0.2, 0, 0, 1),
        child: button,
      ),
    );
  }
}
