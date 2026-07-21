import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/local_prefs.dart';
import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import 'config_panel.dart';
import 'history_panel.dart';
import 'pages_panel.dart';
import 'profiles_panel.dart';
import 'security_panel.dart';
import 'session_header.dart';
import 'session_summary_dialog.dart';
import 'sidebar.dart';
import 'sites_panel.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _section = 'painel';
  LocalPrefs? _prefs;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await LocalPrefs.open();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _locked = prefs.pinEnabled && (prefs.pin?.isNotEmpty ?? false);
    });
  }

  void _refreshPrefs() => setState(() {});

  @override
  Widget build(BuildContext context) {
    if (_locked && _prefs?.pin != null) {
      return PinLockGate(
        pin: _prefs!.pin!,
        onUnlocked: () => setState(() => _locked = false),
        onPinCleared: () async {
          final prefs = await LocalPrefs.open();
          if (!mounted) return;
          setState(() {
            _prefs = prefs;
            _locked = false;
          });
        },
      );
    }

    return Scaffold(
      body: BlocListener<ShieldCubit, ShieldState>(
        listenWhen: (prev, next) =>
            next.lastSummary != null &&
            next.lastSummary?.id != prev.lastSummary?.id,
        listener: (context, state) {
          final summary = state.lastSummary;
          if (summary == null) return;
          showSessionSummaryDialog(context, summary).then((_) {
            if (context.mounted) {
              context.read<ShieldCubit>().clearLastSummary();
            }
          });
        },
        child: Row(
          children: [
            AppSidebar(
              section: _section,
              onSelect: (id) => setState(() => _section = id),
            ),
            Expanded(
              child: Column(
                children: [
                  const SessionHeader(),
                  BlocBuilder<ShieldCubit, ShieldState>(
                    builder: (context, state) {
                      if (state.error == null) return const SizedBox.shrink();
                      return Material(
                        color: AtShieldColors.accentDim,
                        child: ListTile(
                          dense: true,
                          title: Text(
                            state.error!,
                            style: const TextStyle(fontSize: 13),
                          ),
                          trailing: TextButton(
                            onPressed: () =>
                                context.read<ShieldCubit>().boot(),
                            child: const Text('Reconectar'),
                          ),
                        ),
                      );
                    },
                  ),
                  Expanded(child: _body()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case 'painel':
        return const SitesPanel();
      case 'perfis':
        return const ProfilesPanel();
      case 'historico':
        return const HistoryPanel();
      case 'paginas':
        return const PagesPanel();
      case 'seguranca':
        return SecurityPanel(
          prefs: _prefs,
          onPrefsChanged: _refreshPrefs,
          onLock: () => setState(() => _locked = true),
        );
      case 'config':
        return ConfigPanel(
          prefs: _prefs,
          onPrefsChanged: _refreshPrefs,
        );
      default:
        return const SitesPanel();
    }
  }
}
