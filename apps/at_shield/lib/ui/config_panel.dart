import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/local_prefs.dart';
import '../engine/models.dart';
import '../engine/pick_html.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';
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
          title: s.settings,
          subtitle: s.settingsSubtitle,
          child: ListView(
            children: [
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.service,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    _kv(
                      s.status,
                      state.connected ? s.online : s.offline,
                      valueColor: state.connected
                          ? AtShieldColors.success
                          : AtShieldColors.accent,
                    ),
                    _kv(
                      s.protection,
                      !state.protectionActive && state.enabledSitesTotal == 0
                          ? s.protectionInactive
                          : state.networkArmed
                              ? s.protectionActiveNetwork
                              : s.protectionConfiguredNeedsAdmin,
                      valueColor: state.networkArmed
                          ? AtShieldColors.success
                          : (state.protectionActive ||
                                  state.enabledSitesTotal > 0)
                              ? const Color(0xFFEAB308)
                              : AtShieldColors.muted,
                    ),
                    _kv(s.version, state.version),
                    _kv(s.ipc, '127.0.0.1:47830'),
                    _kv(s.previewHtml, '127.0.0.1:47831'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AtRedButton(
                          label: s.reconnect,
                          icon: Icons.refresh,
                          dense: true,
                          onPressed: () =>
                              context.read<ShieldCubit>().boot(),
                        ),
                        AtRedButton(
                          label: s.openPreview,
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
                    Text(
                      s.preferences,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _toggleRow(
                      title: s.minimizeToTray,
                      subtitle: s.minimizeToTraySub,
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
                      title: s.startMinimized,
                      subtitle: prefs?.minimizeToTray == true
                          ? s.startMinimizedSubEnabled
                          : s.startMinimizedSubDisabled,
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
                      title: s.launchWithWindows,
                      subtitle: s.launchWithWindowsSub,
                      value: prefs?.launchWithWindows ?? false,
                      onChanged: prefs == null
                          ? null
                          : (v) async {
                              await prefs!.setLaunchWithWindows(v);
                              onPrefsChanged();
                            },
                    ),
                    const Divider(color: AtShieldColors.border, height: 20),
                    Text(
                      s.language,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _LangButton(
                          label: s.languagePt,
                          selected: LocaleController.instance.lang == AppLang.pt,
                          onPressed: () async {
                            await LocaleController.instance.setLang(AppLang.pt);
                            onPrefsChanged();
                          },
                        ),
                        _LangButton(
                          label: s.languageEn,
                          selected: LocaleController.instance.lang == AppLang.en,
                          onPressed: () async {
                            await LocaleController.instance.setLang(AppLang.en);
                            onPrefsChanged();
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                s.configFootnote,
                style: const TextStyle(color: AtShieldColors.muted, fontSize: 12),
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

class _LangButton extends StatelessWidget {
  const _LangButton({
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected
            ? AtShieldColors.accent.withValues(alpha: 0.15)
            : Colors.transparent,
        side: BorderSide(
          color: selected ? AtShieldColors.accent : AtShieldColors.border,
        ),
      ),
      child: Text(label),
    );
  }
}
