import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/domain_util.dart';
import '../engine/models.dart';
import '../engine/shield_cubit.dart';

class SitesPanel extends StatelessWidget {
  const SitesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        final cubit = context.read<ShieldCubit>();
        final sites = state.filteredSites;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Sites bloqueados (${sites.length})',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontSize: 22,
                        ),
                  ),
                  const Spacer(),
                  AtRedButton(
                    label: 'Adicionar site',
                    icon: Icons.add,
                    dense: true,
                    onPressed: () => _addSite(context),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 220,
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Buscar site...',
                        prefixIcon: Icon(Icons.search, size: 18),
                        isDense: true,
                      ),
                      onChanged: cubit.setQuery,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Ativar todos',
                    onPressed: () => cubit.toggleAll(true),
                    icon: const Icon(Icons.done_all, size: 18),
                  ),
                  IconButton(
                    tooltip: 'Desativar todos',
                    onPressed: () => cubit.toggleAll(false),
                    icon: const Icon(Icons.remove_done, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _HeaderRow(),
              const SizedBox(height: 4),
              Expanded(
                flex: 3,
                child: ListView.builder(
                  itemCount: sites.length,
                  itemBuilder: (context, i) {
                    final site = sites[i];
                    final selected = site.id == state.selectedSiteId;
                    return _SiteRow(
                      site: site,
                      selected: selected,
                      onTap: () => cubit.selectSite(site.id),
                      onToggle: (v) => cubit.toggleSite(site.id, v),
                      onDelete: () => _confirmDelete(context, site),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 2,
                child: SiteProperties(
                  key: ValueKey(state.selectedSiteId ?? 'none'),
                  site: state.selectedSite,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _addSite(BuildContext context) async {
    final cubit = context.read<ShieldCubit>();
    if (!cubit.state.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Serviço offline — não dá pra adicionar site'),
        ),
      );
      return;
    }
    if (cubit.state.activeProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nenhum perfil ativo')),
      );
      return;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: const Text('Adicionar site'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'x.com  ou  https://x.com/',
          ),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          AtRedButton(
            label: 'Adicionar',
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    final domain = normalizeDomain(controller.text);
    controller.dispose();
    if (ok != true) return;
    if (!context.mounted) return;
    if (domain.isEmpty || !domain.contains('.')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Domínio inválido — use x.com')),
      );
      return;
    }

    final existing = cubit.findSiteByDomain(domain);
    if (existing != null) {
      if (!existing.enabled) {
        await cubit.toggleSite(existing.id, true);
      }
      cubit.selectSite(existing.id);
      cubit.setQuery('');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing.enabled
                ? '$domain já está na lista — selecionei ele'
                : '$domain já estava na lista — reativei e selecionei',
          ),
          backgroundColor: AtShieldColors.surface2,
        ),
      );
      return;
    }

    final site = SiteRule(
      id: 'new-${DateTime.now().millisecondsSinceEpoch}',
      profileId: cubit.state.activeProfileId!,
      domain: domain,
    );
    await cubit.saveSite(site);
    if (!context.mounted) return;
    final err = cubit.state.error;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(err ?? 'Site $domain adicionado'),
        backgroundColor:
            err == null ? AtShieldColors.surface2 : AtShieldColors.accentDim,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, SiteRule site) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: const Text('Excluir site'),
        content: Text(
          site.domain == 'x.com' || site.domain == 'twitter.com'
              ? 'Remover ${site.domain} e o alias twitter/x da lista?'
              : 'Remover ${site.domain} da lista de bloqueio?',
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
    if (ok == true && context.mounted) {
      await context.read<ShieldCubit>().deleteSite(site.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${site.domain} removido')),
        );
      }
    }
  }
}

class _HeaderRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('SITE / DOMÍNIO', style: _h)),
          Expanded(flex: 2, child: Text('REDIRECIONAR PARA', style: _h)),
          Expanded(child: Text('PÁGINA', style: _h)),
          SizedBox(width: 72, child: Text('STATUS', style: _h)),
          SizedBox(width: 40),
        ],
      ),
    );
  }
}

const _h = TextStyle(
  fontSize: 10,
  letterSpacing: 0.12,
  fontWeight: FontWeight.w700,
  color: AtShieldColors.muted,
);

class _SiteRow extends StatelessWidget {
  const _SiteRow({
    required this.site,
    required this.selected,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final SiteRule site;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AtShieldColors.accent.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AtShieldColors.accent : Colors.transparent,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AtShieldColors.surface2,
                      child: Text(
                        site.domain.isNotEmpty
                            ? site.domain[0].toUpperCase()
                            : '?',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            site.domain,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          Text(
                            'https://${site.domain}',
                            style: const TextStyle(
                              color: AtShieldColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  site.redirect == RedirectTarget.customPage
                      ? 'Página personalizada'
                      : 'Bloquear',
                  style: const TextStyle(color: AtShieldColors.muted),
                ),
              ),
              Expanded(
                child: Text(
                  site.pageFile,
                  style: const TextStyle(
                    fontFamily: 'Consolas',
                    color: AtShieldColors.muted,
                  ),
                ),
              ),
              SizedBox(
                width: 72,
                child: AtToggle(value: site.enabled, onChanged: onToggle),
              ),
              SizedBox(
                width: 40,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AtShieldColors.muted,
                  ),
                  color: AtShieldColors.surface2,
                  onSelected: (v) {
                    if (v == 'delete') onDelete();
                    if (v == 'toggle') onToggle(!site.enabled);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(site.enabled ? 'Desativar' : 'Ativar'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Excluir'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SiteProperties extends StatefulWidget {
  const SiteProperties({super.key, required this.site});

  final SiteRule? site;

  @override
  State<SiteProperties> createState() => _SitePropertiesState();
}

class _SitePropertiesState extends State<SiteProperties> {
  late TextEditingController _domain;
  String _page = 'foco.html';
  bool _subdomains = true;
  bool _http = false;
  bool _https = true;
  bool _enabled = true;
  RedirectTarget _redirect = RedirectTarget.customPage;

  @override
  void initState() {
    super.initState();
    _domain = TextEditingController();
    _sync(widget.site);
  }

  @override
  void didUpdateWidget(covariant SiteProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site?.id != widget.site?.id) {
      _sync(widget.site);
    }
  }

  void _sync(SiteRule? s) {
    if (s == null) return;
    _domain.text = s.domain;
    _page = s.pageFile;
    _subdomains = s.includeSubdomains;
    _http = s.http;
    _https = s.https;
    _enabled = s.enabled;
    _redirect = s.redirect;
  }

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    if (site == null) {
      return Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AtShieldColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AtShieldColors.border),
        ),
        child: const Text(
          'Selecione um site',
          style: TextStyle(color: AtShieldColors.muted),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AtShieldColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AtShieldColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: AtShieldColors.surface2,
                child: Text(site.domain[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Text(
                site.domain,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AtShieldColors.accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _enabled ? 'Ativo' : 'Inativo',
                  style: const TextStyle(
                    color: AtShieldColors.accent,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Spacer(),
              const Text('Status', style: TextStyle(color: AtShieldColors.muted)),
              AtToggle(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: _field(
                    'Domínio',
                    TextField(controller: _domain),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Incluir subdomínios',
                    DropdownButtonFormField<bool>(
                      initialValue: _subdomains,
                      dropdownColor: AtShieldColors.surface2,
                      items: const [
                        DropdownMenuItem(
                          value: true,
                          child: Text('Sim (recomendado)'),
                        ),
                        DropdownMenuItem(value: false, child: Text('Não')),
                      ],
                      onChanged: (v) =>
                          setState(() => _subdomains = v ?? true),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Redirecionar para',
                    DropdownButtonFormField<RedirectTarget>(
                      initialValue: _redirect,
                      dropdownColor: AtShieldColors.surface2,
                      items: const [
                        DropdownMenuItem(
                          value: RedirectTarget.customPage,
                          child: Text('Página personalizada'),
                        ),
                        DropdownMenuItem(
                          value: RedirectTarget.block,
                          child: Text('Bloquear'),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _redirect = v ?? RedirectTarget.customPage),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _field(
                    'Arquivo da página',
                    DropdownButtonFormField<String>(
                      initialValue: _page,
                      dropdownColor: AtShieldColors.surface2,
                      items: const [
                        DropdownMenuItem(
                          value: 'foco.html',
                          child: Text('foco.html'),
                        ),
                        DropdownMenuItem(
                          value: 'detox.html',
                          child: Text('detox.html'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _page = v ?? 'foco.html'),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Checkbox(
                value: _http,
                activeColor: AtShieldColors.accent,
                onChanged: (v) => setState(() => _http = v ?? false),
              ),
              const Text('http'),
              Checkbox(
                value: _https,
                activeColor: AtShieldColors.accent,
                onChanged: (v) => setState(() => _https = v ?? true),
              ),
              const Text('https'),
              const Spacer(),
              AtRedButton(
                label: 'Excluir site',
                icon: Icons.delete_outline,
                outlined: true,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: AtShieldColors.surface,
                      title: const Text('Excluir site'),
                      content: Text(
                        site.domain == 'x.com' || site.domain == 'twitter.com'
                            ? 'Remover ${site.domain} e o alias twitter/x da lista?'
                            : 'Remover ${site.domain} da lista de bloqueio?',
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
                  if (ok == true && context.mounted) {
                    await context.read<ShieldCubit>().deleteSite(site.id);
                  }
                },
              ),
              const SizedBox(width: 10),
              AtRedButton(
                label: 'Salvar alterações',
                icon: Icons.save_outlined,
                onPressed: () {
                  final updated = site.copyWith(
                    pageFile: _page,
                    enabled: _enabled,
                    includeSubdomains: _subdomains,
                    redirect: _redirect,
                    http: _http,
                    https: _https,
                  );
                  // domain edit via new SiteRule
                  final toSave = SiteRule(
                    id: updated.id,
                    profileId: updated.profileId,
                    domain: _domain.text.trim().toLowerCase(),
                    includeSubdomains: updated.includeSubdomains,
                    redirect: updated.redirect,
                    pageFile: updated.pageFile,
                    http: updated.http,
                    https: updated.https,
                    enabled: updated.enabled,
                  );
                  context.read<ShieldCubit>().saveSite(toSave);
                },
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Os arquivos devem estar dentro da pasta /pages',
              style: TextStyle(color: AtShieldColors.muted, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AtShieldColors.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
