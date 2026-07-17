import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';

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
            'Trabalho';
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
                      title: 'SESSÃO ATIVA',
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: state.activeProfileId,
                          dropdownColor: AtShieldColors.surface2,
                          items: state.profiles
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text('Perfil: ${p.name}'),
                                ),
                              )
                              .toList(),
                          onChanged: (id) {
                            if (id != null) cubit.selectProfile(id);
                          },
                          hint: Text('Perfil: $profileName'),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    _SessionCard(
                      title: 'TEMPO RESTANTE',
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
                  label: 'Iniciar sessão',
                  icon: Icons.play_arrow,
                  onPressed: () => cubit.startSession(),
                ),
              ] else ...[
                AtRedButton(
                  label: session.state == SessionState.paused ? 'Retomar' : 'Pausar',
                  icon: session.state == SessionState.paused
                      ? Icons.play_arrow
                      : Icons.pause,
                  outlined: true,
                  onPressed: () {
                    if (session.state == SessionState.paused) {
                      cubit.resumeSession();
                    } else {
                      cubit.pauseSession();
                    }
                  },
                ),
                const SizedBox(width: 10),
                AtRedButton(
                  label: 'Encerrar sessão',
                  icon: Icons.stop,
                  outlined: true,
                  onPressed: () => cubit.endSession(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
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
