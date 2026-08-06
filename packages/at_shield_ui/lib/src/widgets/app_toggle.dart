import 'package:flutter/material.dart';
import '../theme.dart';

/// Toggle no estilo do protótipo HTML (pill 40×24), sem Switch Material.
class AtToggle extends StatelessWidget {
  const AtToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Semantics(
      button: true,
      toggled: value,
      enabled: enabled,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: GestureDetector(
          onTap: enabled ? () => onChanged!(!value) : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.45,
            child: AnimatedContainer(
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              curve: const Cubic(0.2, 0, 0, 1),
              width: 40,
              height: 24,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: value
                    ? AtShieldColors.accent
                    : AtShieldColors.surface2,
                border: Border.all(
                  color: value
                      ? AtShieldColors.accent
                      : AtShieldColors.border,
                ),
              ),
              child: AnimatedAlign(
                duration: reduce
                    ? Duration.zero
                    : const Duration(milliseconds: 160),
                curve: const Cubic(0.2, 0, 0, 1),
                alignment:
                    value ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: value ? Colors.white : AtShieldColors.muted,
                    shape: BoxShape.circle,
                    boxShadow: value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.25),
                              blurRadius: 2,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
