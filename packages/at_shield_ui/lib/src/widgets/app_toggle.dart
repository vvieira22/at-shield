import 'package:flutter/material.dart';
import '../theme.dart';

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
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: Colors.white,
      activeTrackColor: AtShieldColors.accent,
      inactiveThumbColor: AtShieldColors.muted,
      inactiveTrackColor: AtShieldColors.surface2,
    );
  }
}
