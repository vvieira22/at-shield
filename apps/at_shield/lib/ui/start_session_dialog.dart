import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';

/// Confirm before arming WFP/hosts — anti-cheat and unsigned-build caveats.
Future<void> requestStartSession(
  BuildContext context, {
  String? profileId,
}) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AtShieldColors.surface,
      title: Text(s.startSessionTitle),
      content: Text(s.startSessionContent),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(s.cancel),
        ),
        AtRedButton(
          label: s.start,
          dense: true,
          onPressed: () => Navigator.pop(ctx, true),
        ),
      ],
    ),
  );
  if (confirm != true || !context.mounted) return;
  await context.read<ShieldCubit>().startSession(profileId: profileId);
}
