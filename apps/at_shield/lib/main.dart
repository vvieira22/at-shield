import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'engine/models.dart';
import 'engine/shield_cubit.dart';
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
    _windowChannel.setMethodCallHandler(_onWindowCall);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncTrayTip(_cubit.state);
    });
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    _cubit.close();
    super.dispose();
  }

  Future<void> _syncTrayTip(ShieldState state) async {
    final session = state.session;
    final tip = session == null
        ? 'A.T. Shield'
        : 'A.T. Shield · Protegendo (${session.profileName}) · ${session.remainingLabel}';
    try {
      await _windowChannel.invokeMethod<void>('setTrayTip', tip);
    } catch (_) {}
  }

  Future<dynamic> _onWindowCall(MethodCall call) async {
    if (call.method != 'closeRequested') return null;

    final ctx = _navKey.currentContext;
    final sessionOn = _cubit.state.session != null;

    if (sessionOn && ctx != null && ctx.mounted) {
      final ok = await showDialog<bool>(
        context: ctx,
        barrierDismissible: false,
        builder: (dCtx) => AlertDialog(
          backgroundColor: AtShieldColors.surface,
          title: const Text('Fechar o A.T. Shield?'),
          content: const Text(
            'Tem uma sessão de proteção ativa. '
            'Se fechar agora, o bloqueio para e os sites voltam a abrir.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: const Text('Cancelar'),
            ),
            AtRedButton(
              label: 'Fechar e parar',
              dense: true,
              onPressed: () => Navigator.pop(dCtx, true),
            ),
          ],
        ),
      );
      if (ok != true) return null;
    }

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
        child: MaterialApp(
          navigatorKey: _navKey,
          title: 'A.T. Shield',
          debugShowCheckedModeBanner: false,
          theme: AtShieldTheme.dark(),
          home: const SplashGate(),
        ),
      ),
    );
  }
}
