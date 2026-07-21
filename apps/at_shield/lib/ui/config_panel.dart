import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/local_prefs.dart';
import '../engine/models.dart';
import '../engine/pick_html.dart';
import '../engine/shield_cubit.dart';
import 'section_frame.dart';

class ConfigPanel extends StatelessWidget {
  const ConfigPanel({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
  });

  final LocalPrefs? prefs;
  final VoidCallback onPrefsChanged;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        return SectionFrame(
          title: 'Configurações',
          subtitle: 'Serviço, IPC e preferências locais da UI.',
          child: ListView(
            children: [
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Serviço',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    _kv(
                      'Status',
                      state.connected ? 'Online' : 'Offline',
                      valueColor: state.connected
                          ? AtShieldColors.success
                          : AtShieldColors.accent,
                    ),
                    _kv(
                      'Proteção',
                      !state.protectionActive && state.enabledSitesTotal == 0
                          ? 'Inativa'
                          : state.networkArmed
                              ? 'Ativa (rede)'
                              : 'Configurado · precisa Admin',
                      valueColor: state.networkArmed
                          ? AtShieldColors.success
                          : (state.protectionActive ||
                                  state.enabledSitesTotal > 0)
                              ? const Color(0xFFEAB308)
                              : AtShieldColors.muted,
                    ),
                    _kv('Versão', state.version),
                    _kv('IPC', '127.0.0.1:47830'),
                    _kv('Preview HTML', '127.0.0.1:47831'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AtRedButton(
                          label: 'Reconectar',
                          icon: Icons.refresh,
                          dense: true,
                          onPressed: () =>
                              context.read<ShieldCubit>().boot(),
                        ),
                        AtRedButton(
                          label: 'Abrir preview',
                          icon: Icons.open_in_browser,
                          dense: true,
                          outlined: true,
                          onPressed: () => openPagePreview('foco.html'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preferências',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      title: 'Minimizar para a bandeja',
                      subtitle:
                          'Minimizar ou fechar (X) esconde na bandeja e continua rodando',
                      value: prefs?.minimizeToTray ?? false,
                      onChanged: prefs == null
                          ? null
                          : (v) async {
                              await prefs!.setMinimizeToTray(v);
                              onPrefsChanged();
                            },
                    ),
                    const Divider(color: AtShieldColors.border, height: 20),
                    _toggleRow(
                      title: 'Iniciar na bandeja',
                      subtitle: prefs?.minimizeToTray == true
                          ? 'Abre direto na bandeja do sistema'
                          : 'Ative “Minimizar para a bandeja” antes',
                      value: prefs?.startMinimized ?? false,
                      onChanged: prefs == null || prefs?.minimizeToTray != true
                          ? null
                          : (v) async {
                              await prefs!.setStartMinimized(v);
                              onPrefsChanged();
                            },
                    ),
                    const Divider(color: AtShieldColors.border, height: 20),
                    _toggleRow(
                      title: 'Abrir com o Windows',
                      subtitle: 'Preferência salva — registro no instalador',
                      value: prefs?.launchWithWindows ?? false,
                      onChanged: prefs == null
                          ? null
                          : (v) async {
                              await prefs!.setLaunchWithWindows(v);
                              onPrefsChanged();
                            },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Rode scripts\\dev-windows.bat pra subir UI + serviço. '
                'Redirect de página personalizada precisa de Admin.',
                style: TextStyle(color: AtShieldColors.muted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _kv(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              k,
              style: const TextStyle(color: AtShieldColors.muted, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontFamily: 'Consolas',
                fontSize: 13,
                color: valueColor ?? AtShieldColors.text,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AtShieldColors.muted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        AtToggle(value: value, onChanged: onChanged),
      ],
    );
  }
}
