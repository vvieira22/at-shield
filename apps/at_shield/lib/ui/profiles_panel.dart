import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import 'section_frame.dart';

class ProfilesPanel extends StatelessWidget {
  const ProfilesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        final cubit = context.read<ShieldCubit>();
        final locked = state.editingLocked;
        return SectionFrame(
          title: 'Perfis',
          subtitle:
              'Marque os sites, depois inicie a sessão pra bloquear. Edição só com sessão desligada.',
          actions: [
            AtRedButton(
              label: 'Novo perfil',
              icon: Icons.add,
              dense: true,
              onPressed: locked ? null : () => _editProfile(context),
            ),
          ],
          child: ListView.separated(
            itemCount: state.profiles.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final p = state.profiles[i];
              final active = p.id == state.activeProfileId;
              final stats =
                  state.profileStats[p.id] ?? const ProfileStats();
              return SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: active
                              ? AtShieldColors.accent.withValues(alpha: 0.25)
                              : AtShieldColors.surface2,
                          child: Text(
                            p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                            style: TextStyle(
                              color: active
                                  ? AtShieldColors.accent
                                  : AtShieldColors.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      p.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 15,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (active) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AtShieldColors.accent
                                            .withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: const Text(
                                        'Em uso',
                                        style: TextStyle(
                                          color: AtShieldColors.accent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                stats.total == 0
                                    ? 'Nenhum site ainda'
                                    : '${stats.enabled} de ${stats.total} sites ligados',
                                style: const TextStyle(
                                  color: AtShieldColors.muted,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Mais ações',
                          enabled: !locked,
                          color: AtShieldColors.surface2,
                          onSelected: (v) => _onMenu(context, p, v),
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'rename',
                              child: Text('Renomear'),
                            ),
                            const PopupMenuItem(
                              value: 'duplicate',
                              child: Text('Duplicar'),
                            ),
                            const PopupMenuItem(
                              value: 'enable_all',
                              child: Text('Ligar todos os sites'),
                            ),
                            const PopupMenuItem(
                              value: 'disable_all',
                              child: Text('Desligar todos os sites'),
                            ),
                            if (state.profiles.length > 1)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('Excluir perfil'),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AtRedButton(
                          label: active ? 'Painel' : 'Usar este',
                          dense: true,
                          outlined: active,
                          onPressed: locked
                              ? null
                              : () async {
                                  await cubit.selectProfile(p.id);
                                  if (!context.mounted) return;
                                  if (active) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Perfil já em uso — veja os sites no Painel',
                                        ),
                                        backgroundColor: AtShieldColors.surface2,
                                      ),
                                    );
                                  }
                                },
                        ),
                        AtRedButton(
                          label: 'Iniciar sessão',
                          icon: Icons.play_arrow,
                          dense: true,
                          onPressed: locked
                              ? null
                              : () => cubit.startSession(profileId: p.id),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _onMenu(
    BuildContext context,
    Profile p,
    String action,
  ) async {
    final cubit = context.read<ShieldCubit>();
    switch (action) {
      case 'rename':
        await _editProfile(context, existing: p);
        return;
      case 'duplicate':
        await cubit.duplicateProfile(p);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Perfil ${p.name} duplicado'),
              backgroundColor: AtShieldColors.surface2,
            ),
          );
        }
        return;
      case 'enable_all':
        await cubit.setProfileSitesEnabled(p.id, true);
        return;
      case 'disable_all':
        await cubit.setProfileSitesEnabled(p.id, false);
        return;
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AtShieldColors.surface,
            title: const Text('Excluir perfil'),
            content: Text(
              'Apagar "${p.name}" e todos os sites dele?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar'),
              ),
              AtRedButton(
                label: 'Excluir',
                dense: true,
                onPressed: () => Navigator.pop(ctx, true),
              ),
            ],
          ),
        );
        if (ok == true) await cubit.deleteProfile(p.id);
        return;
    }
  }

  Future<void> _editProfile(BuildContext context, {Profile? existing}) async {
    final cubit = context.read<ShieldCubit>();
    final controller = TextEditingController(text: existing?.name ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(existing == null ? 'Novo perfil' : 'Renomear perfil'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Nome do perfil'),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          AtRedButton(
            label: existing == null ? 'Criar' : 'Salvar',
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final name = controller.text.trim();
    controller.dispose();
    if (ok != true || name.isEmpty) return;
    final profile = Profile(
      id: existing?.id ??
          'profile-${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      sortOrder: existing?.sortOrder ?? cubit.state.profiles.length,
    );
    await cubit.saveProfile(profile);
    if (existing == null && context.mounted) {
      await cubit.selectProfile(profile.id);
    }
  }
}
