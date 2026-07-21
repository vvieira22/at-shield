import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';

import '../engine/models.dart';

Future<void> showSessionSummaryDialog(
  BuildContext context,
  SessionRecord record,
) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: AtShieldColors.surface,
      title: const Text('Sessão encerrada'),
      content: SizedBox(
        width: 420,
        child: SessionSummaryBody(record: record),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}

class SessionSummaryBody extends StatelessWidget {
  const SessionSummaryBody({super.key, required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Proteção · ${record.profileName}',
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${record.dateLabel}  ·  ${record.timeRangeLabel}',
          style: const TextStyle(color: AtShieldColors.muted, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          record.reasonLabel,
          style: const TextStyle(color: AtShieldColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        Text(
          record.totalAttempts == 0
              ? 'Nenhuma tentativa de acesso aos sites bloqueados.'
              : '${record.totalAttempts} tentativa${record.totalAttempts == 1 ? '' : 's'} de entrar em sites bloqueados:',
          style: const TextStyle(fontSize: 13),
        ),
        if (record.attempts.isNotEmpty) ...[
          const SizedBox(height: 10),
          ...record.attempts.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      a.domain,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Text(
                    '${a.count}×',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AtShieldColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}
