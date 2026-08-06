import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/domain_util.dart';
import '../engine/models.dart';
import '../engine/pick_html.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';

class SitesPanel extends StatelessWidget {
  const SitesPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        final cubit = context.read<ShieldCubit>();
        final sites = state.filteredSites;
        final locked = state.editingLocked;
        return Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                s.sitesBlocked(sites.length),
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(fontSize: 22),
              ),
              if (locked) ...[
                const SizedBox(height: 8),
                Text(
                  s.sessionActiveEditSites,
                  style: const TextStyle(
                    color: AtShieldColors.muted,
                    fontSize: 12,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              _Toolbar(
                locked: locked,
                onAdd: () => _addSite(context),
                onQuery: cubit.setQuery,
                onEnableAll: () => cubit.toggleAll(true),
                onDisableAll: () => cubit.toggleAll(false),
              ),
              const SizedBox(height: 14),
              const _HeaderRow(),
              const SizedBox(height: 2),
              Expanded(
                child: sites.isEmpty
                    ? _EmptySites(
                        connecting: !state.connected,
                        hasQuery: state.query.trim().isNotEmpty,
                        onClear: () => cubit.setQuery(''),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 12),
                        itemCount: sites.length,
                        itemBuilder: (context, i) {
                          final site = sites[i];
                          return _SiteRow(
                            site: site,
                            locked: locked,
                            onTap: () => _openEdit(context, site),
                            onToggle: locked
                                ? null
                                : (v) => cubit.toggleSite(site.id, v),
                            onDelete: locked
                                ? null
                                : () => _confirmDelete(context, site),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openEdit(BuildContext context, SiteRule site) async {
    final cubit = context.read<ShieldCubit>();
    cubit.selectSite(site.id);
    await showSiteEditModal(context, site: site, locked: cubit.state.editingLocked);
    if (context.mounted) cubit.clearSiteSelection();
  }

  Future<void> _addSite(BuildContext context) async {
    final cubit = context.read<ShieldCubit>();
    if (cubit.state.editingLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.endSessionToAddSites)),
      );
      return;
    }
    if (!cubit.state.connected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.serviceOfflineAddSite)),
      );
      return;
    }
    if (cubit.state.activeProfileId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noActiveProfile)),
      );
      return;
    }
    final controller = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.addSiteTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: s.domainHint),
          onSubmitted: (_) => Navigator.pop(ctx, true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.add,
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
        SnackBar(content: Text(s.invalidDomain)),
      );
      return;
    }

    final existing = cubit.findSiteByDomain(domain);
    if (existing != null) {
      if (!existing.enabled) {
        await cubit.toggleSite(existing.id, true);
      }
      if (!context.mounted) return;
      await _openEdit(context, existing);
      cubit.setQuery('');
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            existing.enabled
                ? s.siteAlreadyInList(domain)
                : s.siteReactivatedInList(domain),
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
        content: Text(err ?? s.siteAdded(domain)),
        backgroundColor:
            err == null ? AtShieldColors.surface2 : AtShieldColors.accentDim,
      ),
    );
    if (err == null) {
      final saved = cubit.findSiteByDomain(domain);
      if (saved != null) await _openEdit(context, saved);
    }
  }

  Future<void> _confirmDelete(BuildContext context, SiteRule site) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.deleteSite),
        content: Text(
          site.domain == 'x.com' || site.domain == 'twitter.com'
              ? s.deleteSiteTwitterMsg(site.domain)
              : s.deleteSiteConfirmMsg(site.domain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.delete,
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
          SnackBar(content: Text(s.siteRemoved(site.domain))),
        );
      }
    }
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.locked,
    required this.onAdd,
    required this.onQuery,
    required this.onEnableAll,
    required this.onDisableAll,
  });

  final bool locked;
  final VoidCallback onAdd;
  final ValueChanged<String> onQuery;
  final VoidCallback onEnableAll;
  final VoidCallback onDisableAll;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        AtRedButton(
          label: s.addSite,
          icon: Icons.add,
          dense: true,
          ghost: true,
          onPressed: locked ? null : onAdd,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: TextField(
              decoration: InputDecoration(
                hintText: s.searchSite,
                prefixIcon: const Icon(Icons.search, size: 18),
              ),
              onChanged: onQuery,
            ),
          ),
        ),
        const Spacer(),
        IconButton(
          tooltip: locked ? s.endSessionToEdit : s.enableAll,
          onPressed: locked ? null : onEnableAll,
          icon: const Icon(Icons.done_all, size: 18),
        ),
        IconButton(
          tooltip: locked ? s.endSessionToEdit : s.disableAll,
          onPressed: locked ? null : onDisableAll,
          icon: const Icon(Icons.remove_done, size: 18),
        ),
      ],
    );
  }
}

class _EmptySites extends StatelessWidget {
  const _EmptySites({
    required this.connecting,
    required this.hasQuery,
    required this.onClear,
  });

  final bool connecting;
  final bool hasQuery;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    if (connecting) {
      return Center(
        child: Text(
          s.connecting,
          style: const TextStyle(color: AtShieldColors.muted),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              hasQuery
                  ? (LocaleController.instance.lang == AppLang.pt
                      ? 'Nenhum site encontrado'
                      : 'No sites found')
                  : s.noSitesYet,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasQuery
                  ? (LocaleController.instance.lang == AppLang.pt
                      ? 'Nenhum domínio corresponde à busca. Limpe o filtro ou adicione um site novo.'
                      : 'No domain matches the search. Clear the filter or add a site.')
                  : (LocaleController.instance.lang == AppLang.pt
                      ? 'Adicione um domínio pra começar a bloquear.'
                      : 'Add a domain to start blocking.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AtShieldColors.muted,
                fontSize: 13,
              ),
            ),
            if (hasQuery) ...[
              const SizedBox(height: 16),
              AtRedButton(
                label: LocaleController.instance.lang == AppLang.pt
                    ? 'Limpar busca'
                    : 'Clear search',
                ghost: true,
                dense: true,
                onPressed: onClear,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text(s.headerSite, style: _h)),
          Expanded(flex: 2, child: Text(s.headerRedirect, style: _h)),
          Expanded(child: Text(s.headerPage, style: _h)),
          SizedBox(width: 72, child: Text(s.headerStatus, style: _h)),
          const SizedBox(width: 40),
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

class _SiteRow extends StatefulWidget {
  const _SiteRow({
    required this.site,
    required this.locked,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final SiteRule site;
  final bool locked;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onDelete;

  @override
  State<_SiteRow> createState() => _SiteRowState();
}

class _SiteRowState extends State<_SiteRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Material(
        color: _hover ? AtShieldColors.surface.withValues(alpha: 0.55) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          splashColor: AtShieldColors.accent.withValues(alpha: 0.08),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AtShieldColors.borderSubtle),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: site.enabled
                              ? AtShieldColors.accentDim
                              : AtShieldColors.surface2,
                          border: Border.all(
                            color: site.enabled
                                ? Color.lerp(
                                      AtShieldColors.accent,
                                      AtShieldColors.border,
                                      0.65,
                                    )!
                                : AtShieldColors.borderSubtle,
                          ),
                        ),
                        child: Text(
                          site.domain.isNotEmpty
                              ? site.domain[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.02,
                            color: site.enabled
                                ? const Color(0xFFD4A0A3)
                                : AtShieldColors.text,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              site.domain,
                              style: AtShieldTheme.mono.copyWith(
                                fontWeight: FontWeight.w500,
                                fontSize: 13,
                                color: AtShieldColors.text,
                              ),
                            ),
                            Text(
                              'https://${site.domain}',
                              style: AtShieldTheme.mono.copyWith(
                                color: AtShieldColors.muted,
                                fontSize: 11,
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
                        ? s.customPage
                        : s.block,
                    style: const TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    site.pageFile,
                    style: AtShieldTheme.mono.copyWith(
                      color: AtShieldColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
                SizedBox(
                  width: 72,
                  child: AtToggle(
                    value: site.enabled,
                    onChanged: widget.onToggle,
                  ),
                ),
                SizedBox(
                  width: 40,
                  child: PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    enabled: !widget.locked,
                    icon: const Icon(
                      Icons.more_vert,
                      size: 18,
                      color: AtShieldColors.muted,
                    ),
                    color: AtShieldColors.surface2,
                    onSelected: (v) {
                      if (v == 'delete') widget.onDelete?.call();
                      if (v == 'toggle') {
                        widget.onToggle?.call(!site.enabled);
                      }
                      if (v == 'edit') widget.onTap();
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: Text(
                          LocaleController.instance.lang == AppLang.pt ? 'Editar' : 'Edit',
                        ),
                      ),
                      PopupMenuItem(
                        value: 'toggle',
                        child: Text(site.enabled ? s.disable : s.enable),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(s.delete),
                      ),
                    ],
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

/// Modal central no estilo do HTML (`overlay` + `.modal`), com fade/scale.
Future<void> showSiteEditModal(
  BuildContext context, {
  required SiteRule site,
  required bool locked,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Fechar',
    barrierColor: AtShieldColors.overlay,
    transitionDuration:
        reduce ? Duration.zero : const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, secondary) {
      return Center(
        child: SiteEditModal(
          key: ValueKey(site.id),
          site: site,
          locked: locked,
        ),
      );
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final curved = CurvedAnimation(
        parent: anim,
        curve: const Cubic(0.2, 0, 0, 1),
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class SiteEditModal extends StatefulWidget {
  const SiteEditModal({
    super.key,
    required this.site,
    this.locked = false,
  });

  final SiteRule site;
  final bool locked;

  @override
  State<SiteEditModal> createState() => _SiteEditModalState();
}

class _SiteEditModalState extends State<SiteEditModal> {
  late TextEditingController _domain;
  late TextEditingController _page;
  bool _subdomains = true;
  bool _http = false;
  bool _https = true;
  bool _enabled = true;
  RedirectTarget _redirect = RedirectTarget.customPage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _domain = TextEditingController();
    _page = TextEditingController(text: 'foco.html');
    _sync(widget.site);
  }

  void _sync(SiteRule site) {
    _domain.text = site.domain;
    _page.text = site.pageFile;
    _subdomains = site.includeSubdomains;
    _http = site.http;
    _https = site.https;
    _enabled = site.enabled;
    _redirect = site.redirect;
  }

  @override
  void dispose() {
    _domain.dispose();
    _page.dispose();
    super.dispose();
  }

  Future<void> _confirmDelete() async {
    final site = widget.site;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.deleteSite),
        content: Text(
          site.domain == 'x.com' || site.domain == 'twitter.com'
              ? s.deleteSiteTwitterMsg(site.domain)
              : s.deleteSiteConfirmMsg(site.domain),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.delete,
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<ShieldCubit>().deleteSite(site.id);
      if (mounted) Navigator.of(context).pop();
    }
  }

  Future<void> _save() async {
    if (widget.locked || _saving) return;
    final page = _page.text.trim();
    if (page.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.specifyHtmlFile)),
      );
      return;
    }
    setState(() => _saving = true);
    final site = widget.site;
    await context.read<ShieldCubit>().saveSite(
          SiteRule(
            id: site.id,
            profileId: site.profileId,
            domain: _domain.text.trim().toLowerCase(),
            includeSubdomains: _subdomains,
            redirect: _redirect,
            pageFile: page,
            http: _http,
            https: _https,
            enabled: _enabled,
          ),
        );
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final locked = widget.locked;
    final letter =
        site.domain.isNotEmpty ? site.domain[0].toUpperCase() : '?';

    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: AtShieldColors.surface,
            borderRadius: BorderRadius.circular(AtShieldTheme.modalRadius),
            border: Border.all(color: AtShieldColors.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.55),
                blurRadius: 64,
                offset: const Offset(0, 24),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // head
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 12, 16),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AtShieldColors.surface2,
                        border: Border.all(color: AtShieldColors.borderSubtle),
                      ),
                      child: Text(
                        letter,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            site.domain,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            'https://${site.domain}',
                            style: AtShieldTheme.mono.copyWith(
                              color: AtShieldColors.muted,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AtToggle(
                      value: _enabled,
                      onChanged: locked
                          ? null
                          : (v) => setState(() => _enabled = v),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _enabled ? s.active : s.inactive,
                      style: const TextStyle(
                        color: AtShieldColors.muted,
                        fontSize: 12,
                        letterSpacing: 0.02,
                      ),
                    ),
                    IconButton(
                      tooltip: s.close,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, size: 18),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AtShieldColors.borderSubtle),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (locked)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            s.sitePropertiesReadonly,
                            style: const TextStyle(
                              color: AtShieldColors.muted,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              s.domain,
                              TextField(
                                controller: _domain,
                                enabled: !locked,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              s.subdomains,
                              DropdownButtonFormField<bool>(
                                initialValue: _subdomains,
                                isExpanded: true,
                                dropdownColor: AtShieldColors.surface2,
                                items: [
                                  DropdownMenuItem(
                                    value: true,
                                    child: Text(s.yes),
                                  ),
                                  DropdownMenuItem(
                                    value: false,
                                    child: Text(s.no),
                                  ),
                                ],
                                onChanged: locked
                                    ? null
                                    : (v) => setState(
                                          () => _subdomains = v ?? true,
                                        ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _field(
                              s.redirect,
                              DropdownButtonFormField<RedirectTarget>(
                                initialValue: _redirect,
                                isExpanded: true,
                                dropdownColor: AtShieldColors.surface2,
                                items: [
                                  DropdownMenuItem(
                                    value: RedirectTarget.customPage,
                                    child: Text(s.page),
                                  ),
                                  DropdownMenuItem(
                                    value: RedirectTarget.block,
                                    child: Text(s.block),
                                  ),
                                ],
                                onChanged: locked
                                    ? null
                                    : (v) => setState(
                                          () => _redirect =
                                              v ?? RedirectTarget.customPage,
                                        ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _field(
                              s.blockPage,
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _page,
                                      enabled: !locked,
                                      style: AtShieldTheme.mono.copyWith(
                                        fontSize: 13,
                                        color: AtShieldColors.text,
                                      ),
                                      decoration: const InputDecoration(
                                        hintText: 'foco.html',
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _iconBtn(
                                    tooltip: s.browseHtml,
                                    icon: Icons.folder_open_outlined,
                                    onPressed: locked
                                        ? null
                                        : () async {
                                            final path = await pickHtmlFile();
                                            if (path != null && mounted) {
                                              setState(
                                                () => _page.text = path,
                                              );
                                            }
                                          },
                                  ),
                                  const SizedBox(width: 4),
                                  _iconBtn(
                                    tooltip: s.preview,
                                    icon: Icons.open_in_new,
                                    onPressed: () =>
                                        openPagePreview(_page.text),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      _field(
                        s.protocols,
                        Row(
                          children: [
                            _ProtoChip(
                              label: 'http',
                              selected: _http,
                              onTap: locked
                                  ? null
                                  : () => setState(() => _http = !_http),
                            ),
                            const SizedBox(width: 8),
                            _ProtoChip(
                              label: 'https',
                              selected: _https,
                              onTap: locked
                                  ? null
                                  : () => setState(() => _https = !_https),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: const BoxDecoration(
                  color: AtShieldColors.modalFoot,
                  border: Border(
                    top: BorderSide(color: AtShieldColors.borderSubtle),
                  ),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: locked ? null : _confirmDelete,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: Text(s.delete),
                      style: TextButton.styleFrom(
                        foregroundColor: AtShieldColors.muted,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(s.cancel),
                    ),
                    const SizedBox(width: 8),
                    AtRedButton(
                      label: _saving ? '…' : s.saveChanges,
                      dense: true,
                      onPressed: locked || _saving ? null : _save,
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

  Widget _iconBtn({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AtShieldColors.bg,
        borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
              border: Border.all(color: AtShieldColors.borderSubtle),
            ),
            child: Icon(
              icon,
              size: 16,
              color: onPressed == null
                  ? AtShieldColors.border
                  : AtShieldColors.muted,
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, Widget child) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            letterSpacing: 0.06,
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

class _ProtoChip extends StatelessWidget {
  const _ProtoChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AtShieldColors.accentDim : Colors.transparent,
      borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AtShieldTheme.radiusSm),
            border: Border.all(
              color: selected
                  ? Color.lerp(
                        AtShieldColors.accent,
                        AtShieldColors.border,
                        0.5,
                      )!
                  : AtShieldColors.border,
            ),
          ),
          child: Text(
            label,
            style: AtShieldTheme.mono.copyWith(
              fontSize: 12,
              color: selected ? AtShieldColors.text : AtShieldColors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
