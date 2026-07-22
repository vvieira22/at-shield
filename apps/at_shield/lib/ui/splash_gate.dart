import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';

import 'home_shell.dart';

/// Full-bleed logo for ~2s, then fades into the app.
class SplashGate extends StatefulWidget {
  const SplashGate({super.key});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  bool _appReady = false;
  bool _splashGone = false;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    Future<void>.delayed(const Duration(seconds: 2), () async {
      if (!mounted) return;
      setState(() => _appReady = true);
      await _fade.forward();
      if (!mounted) return;
      setState(() => _splashGone = true);
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_appReady) const HomeShell(),
        if (!_splashGone)
          IgnorePointer(
            child: FadeTransition(
              opacity: Tween<double>(begin: 1, end: 0).animate(
                CurvedAnimation(parent: _fade, curve: Curves.easeOut),
              ),
              child: ColoredBox(
                color: AtShieldColors.bg,
                child: Center(
                  child: Image.asset(
                    'assets/icon.png',
                    width: 264,
                    height: 264,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.shield,
                      size: 120,
                      color: AtShieldColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
