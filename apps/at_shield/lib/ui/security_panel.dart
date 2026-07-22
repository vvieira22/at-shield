import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/local_prefs.dart';
import '../engine/windows_admin.dart';
import '../l10n/locale_controller.dart';
import 'section_frame.dart';

class SecurityPanel extends StatefulWidget {
  const SecurityPanel({
    super.key,
    required this.prefs,
    required this.onPrefsChanged,
    required this.onLock,
  });

  final LocalPrefs? prefs;
  final VoidCallback onPrefsChanged;
  final VoidCallback onLock;

  @override
  State<SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends State<SecurityPanel> {
  @override
  Widget build(BuildContext context) {
    final prefs = widget.prefs;
    if (prefs == null) {
      return SectionFrame(
        title: s.security,
        child: Center(
          child: Text(
            s.securityLoading,
            style: TextStyle(color: AtShieldColors.muted),
          ),
        ),
      );
    }

    final hasPin = prefs.pin != null && prefs.pin!.isNotEmpty;
    final enabled = prefs.pinEnabled && hasPin;

    return SectionFrame(
      title: s.security,
      subtitle: s.securitySubtitle,
      child: ListView(
        children: [
          SurfaceCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.protectWithPin,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        s.protectWithPinSub,
                        style: TextStyle(
                          color: AtShieldColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                AtToggle(
                  value: enabled,
                  onChanged: (v) async {
                    if (v && !hasPin) {
                      final ok = await _setPin(context, prefs);
                      if (!ok) return;
                    }
                    if (!v) {
                      await prefs.setPin(prefs.pin, enabled: false);
                    } else {
                      await prefs.setPin(prefs.pin, enabled: true);
                    }
                    widget.onPrefsChanged();
                  },
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
                  hasPin ? s.pinConfigured : s.noPin,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  hasPin ? s.pinConfiguredSub : s.noPinSub,
                  style: const TextStyle(
                    color: AtShieldColors.muted,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    AtRedButton(
                      label: hasPin ? s.changePin : s.setPin,
                      dense: true,
                      onPressed: () async {
                        final ok = await _setPin(context, prefs);
                        if (ok) widget.onPrefsChanged();
                      },
                    ),
                    if (hasPin)
                      AtRedButton(
                        label: s.removePin,
                        dense: true,
                        outlined: true,
                        onPressed: () async {
                          await prefs.setPin(null, enabled: false);
                          widget.onPrefsChanged();
                        },
                      ),
                    if (enabled)
                      AtRedButton(
                        label: s.lockNow,
                        icon: Icons.lock_outline,
                        dense: true,
                        onPressed: widget.onLock,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            s.securityFootnote,
            style: TextStyle(color: AtShieldColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Future<bool> _setPin(BuildContext context, LocalPrefs prefs) async {
    final pin = TextEditingController();
    final confirm = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.setPinTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: pin,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(hintText: s.pinHint),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: confirm,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(8),
              ],
              decoration: InputDecoration(hintText: s.confirmPinHint),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.save,
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final a = pin.text.trim();
    final b = confirm.text.trim();
    pin.dispose();
    confirm.dispose();
    if (ok != true) return false;
    if (a.length < 4 || a != b) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.invalidPin)),
        );
      }
      return false;
    }
    await prefs.setPin(a, enabled: true);
    return true;
  }
}

/// Full-screen lock until the correct PIN is entered.
class PinLockGate extends StatefulWidget {
  const PinLockGate({
    super.key,
    required this.pin,
    required this.onUnlocked,
    required this.onPinCleared,
  });

  final String pin;
  final VoidCallback onUnlocked;
  final VoidCallback onPinCleared;

  @override
  State<PinLockGate> createState() => _PinLockGateState();
}

class _PinLockGateState extends State<PinLockGate> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    if (_controller.text.trim() == widget.pin) {
      widget.onUnlocked();
      return;
    }
    setState(() => _error = s.pinIncorrect);
    _controller.clear();
  }

  Future<void> _forgotPin() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.resetPinTitle),
        content: Text(s.resetPinContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.reset,
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final cleared = await resetPinWithAdminPrompt();
    if (!mounted) return;
    setState(() => _busy = false);
    if (cleared) {
      widget.onPinCleared();
      return;
    }
    setState(() {
      _error = s.resetPinFailed;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AtShieldColors.bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SurfaceCard(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 36, color: AtShieldColors.accent),
                const SizedBox(height: 14),
                Text(
                  s.appLocked,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  s.enterPinToContinue,
                  style: TextStyle(color: AtShieldColors.muted, fontSize: 13),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _controller,
                  obscureText: true,
                  autofocus: true,
                  enabled: !_busy,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(8),
                  ],
                  decoration: InputDecoration(
                    hintText: 'PIN',
                    errorText: _error,
                  ),
                  onSubmitted: (_) => _tryUnlock(),
                ),
                const SizedBox(height: 14),
                AtRedButton(
                  label: _busy ? s.waitingAdmin : s.unlock,
                  icon: Icons.lock_open,
                  onPressed: _busy ? null : _tryUnlock,
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _busy ? null : _forgotPin,
                  child: Text(
                    s.forgotPin,
                    style: TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
