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

        final reduce = MediaQuery.disableAnimationsOf(context);
        final child = session != null
            ? _ActiveSessionBar(
                key: const ValueKey('session-active'),
                session: session,
                profileName: session.profileName.isNotEmpty
                    ? session.profileName
                    : profileName,
                onEnd: () => _requestEndSession(context, cubit),
              )
            : _IdleSessionBar(
                key: const ValueKey('session-idle'),
                state: state,
                profileName: profileName,
                onProfileChanged: (id) {
                  if (id != null) cubit.selectProfile(id);
                },
                onDurationChanged: cubit.setSessionDurationMins,
                onStart: () => requestStartSession(context),
              );

        return AnimatedSwitcher(
          duration:
              reduce ? Duration.zero : const Duration(milliseconds: 220),
          switchInCurve: const Cubic(0.2, 0, 0, 1),
          switchOutCurve: const Cubic(0.2, 0, 0, 1),
          transitionBuilder: (c, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, -0.04),
                end: Offset.zero,
              ).animate(anim),
              child: c,
            ),
          ),
          child: child,
        );
      },
    );
  }
}

class _IdleSessionBar extends StatelessWidget {
  const _IdleSessionBar({
    super.key,
    required this.state,
    required this.profileName,
    required this.onProfileChanged,
    required this.onDurationChanged,
    required this.onStart,
  });

  final ShieldState state;
  final String profileName;
  final ValueChanged<String?> onProfileChanged;
  final ValueChanged<int> onDurationChanged;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AtShieldColors.borderSubtle),
        ),
      ),
      child: Row(
        children: [
          _FieldChip(
            label: s.activeSession,
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: state.activeProfileId,
                isDense: true,
                dropdownColor: AtShieldColors.surface2,
                style: const TextStyle(
                  color: AtShieldColors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                items: state.profiles
                    .map(
                      (p) => DropdownMenuItem(
                        value: p.id,
                        child: Text(s.profileLabel(p.name)),
                      ),
                    )
                    .toList(),
                onChanged: onProfileChanged,
                hint: Text(s.profileLabel(profileName)),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _FieldChip(
            label: s.duration,
            child: _DurationPicker(
              minutes: state.sessionDurationMins,
              onChanged: onDurationChanged,
            ),
          ),
          const Spacer(),
          AtRedButton(
            label: s.startSession,
            icon: Icons.play_arrow_rounded,
            onPressed: onStart,
          ),
        ],
      ),
    );
  }
}

class _ActiveSessionBar extends StatelessWidget {
  const _ActiveSessionBar({
    super.key,
    required this.session,
    required this.profileName,
    required this.onEnd,
  });

  final FocusSession session;
  final String profileName;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    final remaining = session.durationSecs == 0
        ? 0.0
        : (session.remainingSecs / session.durationSecs).clamp(0.0, 1.0);
    final reduce = MediaQuery.disableAnimationsOf(context);

    return Container(
      height: 64,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      decoration: BoxDecoration(
        color: Color.lerp(AtShieldColors.surface, AtShieldColors.bg, 0.3),
        border: const Border(
          bottom: BorderSide(color: AtShieldColors.borderSubtle),
        ),
      ),
      child: Stack(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _LiveDot(),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.activeSession.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.08,
                              color: AtShieldColors.muted,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profileName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AtShieldColors.text,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CustomPaint(
                      painter: _RingPainter(progress: remaining),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TickingClock(
                        label: session.remainingLabel,
                        tickKey: session.remainingSecs,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.timeRemaining.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.08,
                          color: AtShieldColors.muted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AtRedButton(
                    label: s.endSession,
                    ghost: true,
                    icon: Icons.stop_rounded,
                    onPressed: onEnd,
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: remaining.clamp(0.0, 1.0),
                child: AnimatedContainer(
                  duration: reduce
                      ? Duration.zero
                      : const Duration(milliseconds: 900),
                  curve: Curves.linear,
                  height: 2,
                  color: AtShieldColors.accent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Tick suave a cada segundo (opacity + 1px), como no HTML `.time.is-tick`.
class _TickingClock extends StatelessWidget {
  const _TickingClock({required this.label, required this.tickKey});

  final String label;
  final int tickKey;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.disableAnimationsOf(context);
    return AnimatedSwitcher(
      duration: reduce ? Duration.zero : const Duration(milliseconds: 120),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, anim) {
        return FadeTransition(
          opacity: Tween<double>(begin: 0.55, end: 1).animate(anim),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(anim),
            child: child,
          ),
        );
      },
      child: Text(
        label,
        key: ValueKey(tickKey),
        style: AtShieldTheme.mono.copyWith(
          fontSize: 28,
          fontWeight: FontWeight.w500,
          letterSpacing: -0.03,
          height: 1,
          fontFeatures: const [FontFeature.tabularFigures()],
          color: AtShieldColors.text,
        ),
      ),
    );
  }
}

class _LiveDot extends StatefulWidget {
  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    final reduce = WidgetsBinding.instance.platformDispatcher
        .accessibilityFeatures.reduceMotion;
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    if (!reduce) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = Curves.easeOut.transform(_c.value);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: AtShieldColors.success,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AtShieldColors.success.withValues(alpha: 0.4 * (1 - t)),
                blurRadius: 0,
                spreadRadius: 8 * t,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress});

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide - 3) / 2;
    final track = Paint()
      ..color = AtShieldColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final arc = Paint()
      ..color = AtShieldColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, track);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -1.57079632679, // -90°
      6.28318530718 * progress.clamp(0.0, 1.0),
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.progress != progress;
}

class _FieldChip extends StatelessWidget {
  const _FieldChip({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AtShieldColors.surface,
        borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
        border: Border.all(color: AtShieldColors.borderSubtle),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 0.08,
              fontWeight: FontWeight.w600,
              color: AtShieldColors.muted,
            ),
          ),
          child,
        ],
      ),
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
  if (!context.mounted) return;
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
        isDense: true,
        dropdownColor: AtShieldColors.surface2,
        style: const TextStyle(
          color: AtShieldColors.text,
          fontSize: 13,
          fontWeight: FontWeight.w500,
        ),
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
