import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({super.key, required this.section, required this.onSelect});

  final String section;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
      decoration: const BoxDecoration(
        color: AtShieldColors.sidebar,
        border: Border(
          right: BorderSide(color: AtShieldColors.borderSubtle),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AtShieldTheme.radius),
                child: Image.asset(
                  'assets/icon.png',
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) => Container(
                    width: 48,
                    height: 48,
                    color: AtShieldColors.accent,
                    alignment: Alignment.center,
                    child: const Text(
                      'AT',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'A.T. SHIELD',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.06,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.tagline,
                      style: const TextStyle(
                        color: AtShieldColors.muted,
                        fontSize: 10,
                        letterSpacing: 0.02,
                        height: 1.3,
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
            label: s.navPainel,
            icon: Icons.list_alt_outlined,
            selected: section == 'painel',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'perfis',
            label: s.navPerfis,
            icon: Icons.person_outline,
            selected: section == 'perfis',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'historico',
            label: s.navHistorico,
            icon: Icons.history,
            selected: section == 'historico',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'paginas',
            label: s.navPaginas,
            icon: Icons.web_asset_outlined,
            selected: section == 'paginas',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'seguranca',
            label: s.navSeguranca,
            icon: Icons.shield_outlined,
            selected: section == 'seguranca',
            onTap: onSelect,
          ),
          _NavItem(
            id: 'config',
            label: s.settings,
            icon: Icons.settings_outlined,
            selected: section == 'config',
            onTap: onSelect,
          ),
          const Spacer(),
          BlocBuilder<ShieldCubit, ShieldState>(
            builder: (context, state) {
              final status = _protectionStatus(state);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: status.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          status.label,
                          style: const TextStyle(
                            color: AtShieldColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'A.T. SHIELD v${state.version}',
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontFamilyFallback: [
                        'Cascadia Mono',
                        'SF Mono',
                        'monospace',
                      ],
                      color: AtShieldColors.muted,
                      fontSize: 11,
                      letterSpacing: 0.02,
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

class _ProtStatus {
  const _ProtStatus(this.label, this.color);
  final String label;
  final Color color;
}

_ProtStatus _protectionStatus(ShieldState state) {
  final sessionOn = state.session != null;
  final enabled = state.enabledSitesTotal;
  final localEnabled = state.sites.where((s) => s.enabled).length;

  if (sessionOn && state.networkArmed) {
    return _ProtStatus(s.statusProtecting, AtShieldColors.success);
  }
  if (sessionOn) {
    return _ProtStatus(s.statusSessionNeedsAdmin, AtShieldColors.warn);
  }
  if (state.networkArmed && state.protectionActive) {
    return _ProtStatus(s.statusBlockActive, AtShieldColors.success);
  }
  if (enabled > 0 || localEnabled > 0 || state.protectionActive) {
    return _ProtStatus(s.statusConfiguredNeedsAdmin, AtShieldColors.warn);
  }
  return _ProtStatus(s.statusNoSites, AtShieldColors.muted);
}

class _NavItem extends StatefulWidget {
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
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final reduce = MediaQuery.disableAnimationsOf(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration:
              reduce ? Duration.zero : const Duration(milliseconds: 140),
          curve: const Cubic(0.2, 0, 0, 1),
          decoration: BoxDecoration(
            color: selected
                ? AtShieldColors.accentDim
                : _hover
                    ? AtShieldColors.surface.withValues(alpha: 0.55)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
              onTap: () => widget.onTap(widget.id),
              hoverColor: Colors.transparent,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      widget.icon,
                      size: 18,
                      color: selected
                          ? AtShieldColors.text
                          : AtShieldColors.muted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 13,
                        letterSpacing: 0.01,
                        color: selected
                            ? AtShieldColors.text
                            : AtShieldColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
