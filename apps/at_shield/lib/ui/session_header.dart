import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/local_prefs.dart';
import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';
import 'start_session_dialog.dart';

/// Preset session lengths (minutes). `-1` = clock picker.
const _durationPresets = <int>[15, 30, 60, 180, 360];

class SessionHeader extends StatelessWidget {
  const SessionHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        final cubit = context.read<ShieldCubit>();
        final session = state.session;
        final profileName = state.profiles
                .where((p) => p.id == state.activeProfileId)
                .map((p) => p.name)
                .firstOrNull ??
            s.defaultProfileName;
        final remaining = session?.remainingLabel ?? '00:00';
        final progress = session == null || session.durationSecs == 0
            ? 0.0
            : 1.0 - (session.remainingSecs / session.durationSecs);

        return Container(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AtShieldColors.border)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _SessionCard(
                      title: s.activeSession,
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.activeProfileId,
                          dropdownColor: AtShieldColors.surface2,
                          items: state.profiles
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(s.profileLabel(p.name)),
                                ),
                              )
                              .toList(),
                          onChanged: session != null
                              ? null
                              : (id) {
                                  if (id != null) cubit.selectProfile(id);
                                },
                          hint: Text(s.profileLabel(profileName)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    if (session == null)
                      _SessionCard(
                        title: s.duration,
                        child: _DurationPicker(
                          minutes: state.sessionDurationMins,
                          onChanged: cubit.setSessionDurationMins,
                        ),
                      )
                    else
                      _SessionCard(
                        title: s.timeRemaining,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                strokeWidth: 3,
                                color: AtShieldColors.accent,
                                backgroundColor: AtShieldColors.border,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              remaining,
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (session == null) ...[
                AtRedButton(
                  label: s.startSession,
                  icon: Icons.play_arrow,
                  onPressed: () => requestStartSession(context),
                ),
              ] else ...[
                AtRedButton(
                  label: s.endSession,
                  icon: Icons.stop,
                  outlined: true,
                  onPressed: () => _requestEndSession(context, cubit),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

Future<void> _requestEndSession(
  BuildContext context,
  ShieldCubit cubit,
) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AtShieldColors.surface,
      title: Text(s.endSessionTitle),
      content: Text(s.endSessionContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        AtRedButton(
          label: s.end,
          dense: true,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;

  final prefs = await LocalPrefs.open();
  final pinOn =
      prefs.pinEnabled && prefs.pin != null && prefs.pin!.isNotEmpty;
  if (pinOn) {
    final pinOk = await _askEndPin(context, prefs.pin!);
    if (pinOk != true || !context.mounted) return;
  }

  await cubit.endSession();
}

Future<bool?> _askEndPin(BuildContext context, String expected) {
  final ctrl = TextEditingController();
  String? error;
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          void submit() {
            if (ctrl.text.trim() == expected) {
              Navigator.pop(ctx, true);
              return;
            }
            setLocal(() {
              error = s.pinIncorrect;
              ctrl.clear();
            });
          }

          return AlertDialog(
            backgroundColor: AtShieldColors.surface,
            title: Text(s.confirmPin),
            content: TextField(
              controller: ctrl,
              obscureText: true,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(
                hintText: 'PIN',
                errorText: error,
              ),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel),
              ),
              AtRedButton(
                label: s.confirm,
                dense: true,
                onPressed: submit,
              ),
            ],
          );
        },
      );
    },
  ).whenComplete(ctrl.dispose);
}

class _DurationPicker extends StatelessWidget {
  const _DurationPicker({required this.minutes, required this.onChanged});

  final int minutes;
  final ValueChanged<int> onChanged;

  static String _label(int m) => s.durationLabel(m);

  @override
  Widget build(BuildContext context) {
    final isPreset = _durationPresets.contains(minutes);
    final value = isPreset ? minutes : -1;
    return DropdownButtonHideUnderline(
      child: DropdownButton<int>(
        value: value,
        dropdownColor: AtShieldColors.surface2,
        items: [
          ..._durationPresets.map(
            (m) => DropdownMenuItem(value: m, child: Text(_label(m))),
          ),
          DropdownMenuItem(
            value: -1,
            child: Text(
              isPreset ? s.clockPicker : '${_label(minutes)} · ${s.clockEdit}',
            ),
          ),
        ],
        onChanged: (v) async {
          if (v == null) return;
          if (v == -1) {
            final custom = await _askDurationClock(context, minutes);
            if (custom != null) onChanged(custom);
            return;
          }
          onChanged(v);
        },
      ),
    );
  }
}

/// Dial clock → duração (horas + minutos).
Future<int?> _askDurationClock(BuildContext context, int currentMins) async {
  final clamped = currentMins.clamp(1, 23 * 60 + 59);
  final initial = TimeOfDay(
    hour: clamped ~/ 60,
    minute: clamped % 60,
  );
  final picked = await showTimePicker(
    context: context,
    initialTime: initial,
    initialEntryMode: TimePickerEntryMode.dial,
    helpText: s.durationClock,
    hourLabelText: s.hours,
    minuteLabelText: s.minutes,
    cancelText: s.cancel,
    confirmText: s.ok,
    builder: (ctx, child) {
      return MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: AtShieldColors.accent,
              onPrimary: Colors.white,
              surface: AtShieldColors.surface,
              onSurface: AtShieldColors.text,
              secondary: AtShieldColors.accent,
              onSecondary: Colors.white,
            ),
            timePickerTheme: TimePickerThemeData(
              backgroundColor: AtShieldColors.surface,
              dialBackgroundColor: AtShieldColors.surface2,
              dialHandColor: AtShieldColors.accent,
              dialTextColor: AtShieldColors.text,
              hourMinuteTextColor: AtShieldColors.text,
              hourMinuteColor: AtShieldColors.surface2,
              dayPeriodTextColor: AtShieldColors.text,
              entryModeIconColor: AtShieldColors.muted,
              helpTextStyle: const TextStyle(
                color: AtShieldColors.muted,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.12,
                fontSize: 11,
              ),
            ),
          ),
          child: child!,
        ),
      );
    },
  );
  if (picked == null) return null;
  final total = picked.hour * 60 + picked.minute;
  if (total < 1) return 1;
  return total.clamp(1, 24 * 60);
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AtShieldColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AtShieldColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.14,
              fontWeight: FontWeight.w700,
              color: AtShieldColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
