import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import 'session_header.dart';
import 'sidebar.dart';
import 'sites_panel.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  String _section = 'painel';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          AppSidebar(
            section: _section,
            onSelect: (id) => setState(() => _section = id),
          ),
          Expanded(
            child: Column(
              children: [
                const SessionHeader(),
              BlocBuilder<ShieldCubit, ShieldState>(
                builder: (context, state) {
                  if (state.error == null) return const SizedBox.shrink();
                  return Material(
                    color: AtShieldColors.accentDim,
                    child: ListTile(
                      dense: true,
                      title: Text(state.error!, style: const TextStyle(fontSize: 13)),
                      trailing: TextButton(
                        onPressed: () => context.read<ShieldCubit>().boot(),
                        child: const Text('Reconectar'),
                      ),
                    ),
                  );
                },
              ),
              Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _body() {
    switch (_section) {
      case 'painel':
        return const SitesPanel();
      case 'perfis':
        return const _SimplePage(
          title: 'Perfis',
          body: 'Gerencie perfis no painel — Trabalho, Estudos, Detox.',
        );
      case 'paginas':
        return const _SimplePage(
          title: 'Página de bloqueio',
          body: 'HTML em /pages. Preview: 127.0.0.1:47831. Com "Página personalizada" o hosts aponta o domínio pra cá (precisa Admin).',
        );
      case 'seguranca':
        return const _SimplePage(
          title: 'Segurança',
          body: 'PIN / 2FA — premium (estrutura pronta).',
        );
      case 'config':
        return const _SimplePage(
          title: 'Configurações',
          body: 'Serviço em background: at-shield-service. IPC 127.0.0.1:47830.',
        );
      default:
        return const SitesPanel();
    }
  }
}

class _SimplePage extends StatelessWidget {
  const _SimplePage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Text(body, style: const TextStyle(color: AtShieldColors.muted)),
        ],
      ),
    );
  }
}
