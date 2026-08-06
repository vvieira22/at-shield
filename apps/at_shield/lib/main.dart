import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'engine/models.dart';
import 'engine/shield_cubit.dart';
import 'l10n/locale_controller.dart';
import 'ui/splash_gate.dart';

final _navKey = GlobalKey<NavigatorState>();
const _windowChannel = MethodChannel('at_shield/window');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AtShieldApp());
}

class AtShieldApp extends StatefulWidget {
  const AtShieldApp({super.key});

  @override
  State<AtShieldApp> createState() => _AtShieldAppState();
}

class _AtShieldAppState extends State<AtShieldApp> {
  late final ShieldCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ShieldCubit()..boot();
    LocaleController.instance.load();
    LocaleController.instance.addListener(_onLocaleChanged);
    _windowChannel.setMethodCallHandler(_onWindowCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTrayTip(_cubit.state);
    });
  }

  @override
  void dispose() {
    LocaleController.instance.removeListener(_onLocaleChanged);
    _windowChannel.setMethodCallHandler(null);
    _cubit.close();
    super.dispose();
  }

  void _onLocaleChanged() => _syncTrayTip(_cubit.state);

  Future<void> _syncTrayTip(ShieldState state) async {
    final session = state.session;
    final tip = session == null
        ? s.appName
        : s.trayProtecting(session.profileName, session.remainingLabel);
    try {
      await _windowChannel.invokeMethod<void>('setTrayTip', tip);
    } catch (_) {}
  }

  Future<dynamic> _onWindowCall(MethodCall call) async {
    if (call.method != 'closeRequested') return null;

    final reason = call.arguments is String ? call.arguments as String : 'close';
    final sessionOn = _cubit.state.session != null;

    // Sair da bandeja / sessão ativa: trazer a janela pra frente antes do diálogo.
    if (reason == 'exit' || sessionOn) {
      try {
        await _windowChannel.invokeMethod<void>('showFromTray');
      } catch (_) {}
      // Deixa o frame da janela aparecer antes do modal.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    final ctx = _navKey.currentContext;
    if (sessionOn && ctx != null && ctx.mounted) {
      final ok = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          backgroundColor: AtShieldColors.surface,
          title: Text(s.closeAppTitle),
          content: Text(s.closeAppContent),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(s.cancel),
            ),
            AtRedButton(
              label: s.closeAndStop,
              dense: true,
              onPressed: () => Navigator.pop(dCtx, true),
            ),
          ],
        ),
      );
      if (ok != true) return null;
    } else if (reason != 'exit' && !sessionOn && _cubit.minimizeToTray) {
      // X / taskbar close sem sessão: pode ir pra bandeja.
      await _windowChannel.invokeMethod<void>('hideToTray');
      return null;
    }

    // Solta a rede ANTES de destruir a janela (dispose pode perder a corrida).
    await _cubit.disarmForQuit();
    await _windowChannel.invokeMethod<void>('quit');
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _cubit,
      child: BlocListener<ShieldCubit, ShieldState>(
        listenWhen: (prev, next) =>
            prev.session?.profileName != next.session?.profileName ||
            (prev.session == null) != (next.session == null) ||
            prev.session?.remainingSecs != next.session?.remainingSecs,
        listener: (context, state) => _syncTrayTip(state),
        // Locale rebuilds live under HomeShell — keep MaterialApp stable
        // so splash / navigator aren't remounted on language change.
        child: MaterialApp(
          navigatorKey: _navKey,
          title: s.appName,
          debugShowCheckedModeBanner: false,
          theme: AtShieldTheme.dark(),
          home: const SplashGate(),
        ),
      ),
    );
  }
}
