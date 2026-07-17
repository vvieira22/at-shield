import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.section, required this.onSelect});

  final String section;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      color: AtShieldColors.sidebar,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AtShieldColors.accent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'NERD',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.08,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'A.T. SHIELD',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.06,
                      ),
                    ),
                    Text(
                      'FOCO | DISCIPLINA | PROTEÇÃO',
                      style: TextStyle(
                        color: AtShieldColors.muted,
                        fontSize: 8.5,
                        letterSpacing: 0.04,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),
          _NavItem(
            id: 'painel',
            label: 'Painel',
            icon: Icons.dashboard_outlined,
            selected: section == 'painel',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'perfis',
            label: 'Perfis',
            icon: Icons.person_outline,
            selected: section == 'perfis',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'paginas',
            label: 'Página de bloqueio',
            icon: Icons.web_asset_outlined,
            selected: section == 'paginas',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'seguranca',
            label: 'Segurança',
            icon: Icons.shield_outlined,
            selected: section == 'seguranca',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'config',
            label: 'Configurações',
            icon: Icons.settings_outlined,
            selected: section == 'config',
            onTap: onSelect,
          ),
          const Spacer(),
          BlocBuilder<ShieldCubit, ShieldState>(
            builder: (context, state) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: state.protectionActive
                              ? AtShieldColors.success
                              : AtShieldColors.muted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        state.protectionActive
                            ? 'Proteção ativa'
                            : 'Proteção inativa',
                        style: const TextStyle(
                          color: AtShieldColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A.T. SHIELD v${state.version}',
                    style: const TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? AtShieldColors.accent.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(id),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: selected
                  ? const Border(
                      left: BorderSide(color: AtShieldColors.accent, width: 3),
                    )
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: selected ? AtShieldColors.accent : AtShieldColors.muted,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AtShieldColors.text : AtShieldColors.muted,
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
