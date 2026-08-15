import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'engine/models.dart';
import 'engine/shield_cubit.dart';
import 'engine/window_close.dart';
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
    final action = decideWindowClose(
      reason: reason,
      sessionOn: sessionOn,
      closeMinimizes: _cubit.closeMinimizes,
      minimizeToTray: _cubit.minimizeToTray,
    );

    switch (action) {
      case WindowCloseAction.minimizeTaskbar:
        await _windowChannel.invokeMethod<void>('minimize');
        return null;
      case WindowCloseAction.hideToTray:
        await _windowChannel.invokeMethod<void>('hideToTray');
        return null;
      case WindowCloseAction.quitNow:
        break;
      case WindowCloseAction.confirmQuit:
      case WindowCloseAction.confirmStopSession:
        try {
          await _windowChannel.invokeMethod<void>('showFromTray');
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final ok = await _confirmClose(
          sessionOn: action == WindowCloseAction.confirmStopSession,
        );
        if (ok != true) return null;
    }

    await _cubit.disarmForQuit();
    await _windowChannel.invokeMethod<void>('quit');
    return null;
  }

  Future<bool> _confirmClose({required bool sessionOn}) async {
    final ctx = _navKey.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    final ok = await showDialog<bool>(
      context: ctx,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(sessionOn ? s.closeAppTitle : s.quitAppTitle),
        content: Text(sessionOn ? s.closeAppContent : s.quitAppContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: sessionOn ? s.closeAndStop : s.quitAppConfirm,
            dense: true,
            onPressed: () => Navigator.pop(dCtx, true),
          ),
        ],
      ),
    );
    return ok == true;
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
