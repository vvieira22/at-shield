import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/local_prefs.dart';
import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';
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
  bool _restorePrompted = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferRestore());
  }

  Future<void> _loadPrefs() async {
    final prefs = await LocalPrefs.open();
    if (!mounted) return;
    setState(() {
      _prefs = prefs;
      _locked = prefs.pinEnabled && (prefs.pin?.isNotEmpty ?? false);
    });
    // PIN may have blocked the first frame — offer after unlock path too.
    if (!_locked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeOfferRestore());
    }
  }

  void _refreshPrefs() => setState(() {});

  void _maybeOfferRestore() {
    if (!mounted || _locked || _restorePrompted) return;
    final parked = context.read<ShieldCubit>().state.interruptedSession;
    if (parked == null) return;
    _restorePrompted = true;
    _offerRestore(parked);
  }

  Future<void> _offerRestore(InterruptedSession parked) async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dCtx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.restoreSessionTitle),
        content: Text(
          s.restoreSessionBody(parked.profileName, parked.remainingLabel),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(s.restoreSessionNo),
          ),
          AtRedButton(
            label: s.restoreSessionYes,
            dense: true,
            onPressed: () => Navigator.pop(dCtx, true),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final cubit = context.read<ShieldCubit>();
    if (ok == true) {
      await cubit.restoreInterruptedSession();
    } else {
      await cubit.discardInterruptedSession();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LocaleController.instance,
      builder: (context, _) {
        if (_locked && _prefs?.pin != null) {
          return PinLockGate(
            pin: _prefs!.pin!,
            onUnlocked: () {
              setState(() => _locked = false);
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _maybeOfferRestore());
            },
            onPinCleared: () async {
              final prefs = await LocalPrefs.open();
              if (!mounted) return;
              setState(() {
                _prefs = prefs;
                _locked = false;
              });
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _maybeOfferRestore());
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
            child: BlocListener<ShieldCubit, ShieldState>(
              listenWhen: (prev, next) =>
                  next.interruptedSession != null &&
                  prev.interruptedSession == null,
              listener: (context, state) => _maybeOfferRestore(),
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
                            if (state.error == null) {
                              return const SizedBox.shrink();
                            }
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
                                  child: Text(s.reconnect),
                                ),
                              ),
                            );
                          },
                        ),
                        Expanded(child: _animatedBody()),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _animatedBody() {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
      switchInCurve: const Cubic(0.2, 0, 0, 1),
      switchOutCurve: const Cubic(0.2, 0, 0, 1),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.012, 0),
            end: Offset.zero,
          ).animate(anim),
          child: child,
        ),
      ),
      child: KeyedSubtree(
        key: ValueKey(_section),
        child: _body(),
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
