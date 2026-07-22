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
        final selected = state.selectedSite;
        final locked = state.editingLocked;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          s.sitesBlocked(sites.length),
                          style: Theme.of(context)
                              .textTheme
                              .headlineMedium
                              ?.copyWith(fontSize: 22),
                        ),
                        const Spacer(),
                        AtRedButton(
                          label: s.addSite,
                          icon: Icons.add,
                          dense: true,
                          onPressed: locked ? null : () => _addSite(context),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            decoration: InputDecoration(
                              hintText: s.searchSite,
                              prefixIcon: Icon(Icons.search, size: 18),
                              isDense: true,
                            ),
                            onChanged: cubit.setQuery,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: locked ? s.endSessionToEdit : s.enableAll,
                          onPressed:
                              locked ? null : () => cubit.toggleAll(true),
                          icon: const Icon(Icons.done_all, size: 18),
                        ),
                        IconButton(
                          tooltip: locked ? s.endSessionToEdit : s.disableAll,
                          onPressed:
                              locked ? null : () => cubit.toggleAll(false),
                          icon: const Icon(Icons.remove_done, size: 18),
                        ),
                      ],
                    ),
                    if (locked) ...[
                      const SizedBox(height: 8),
                      Text(
                        s.sessionActiveEditSites,
                        style: TextStyle(
                          color: AtShieldColors.muted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    _HeaderRow(),
                    const SizedBox(height: 4),
                    Expanded(
                      child: sites.isEmpty && !state.connected
                          ? Center(
                              child: Text(
                                s.connecting,
                                style: TextStyle(color: AtShieldColors.muted),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.only(bottom: 12),
                              itemCount: sites.length,
                              itemBuilder: (context, i) {
                                final site = sites[i];
                                return _SiteRow(
                                  site: site,
                                  selected: site.id == state.selectedSiteId,
                                  locked: locked,
                                  onTap: () => cubit.selectSite(site.id),
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
              ),
            ),
            if (selected != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SiteProperties(
                  key: ValueKey(selected.id),
                  site: selected,
                  locked: locked,
                ),
              ),
          ],
        );
      },
    );
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
      cubit.selectSite(existing.id);
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

class _HeaderRow extends StatelessWidget {
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
    required this.locked,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  final SiteRule site;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;
  final ValueChanged<bool>? onToggle;
  final VoidCallback? onDelete;

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
                      ? s.customPage
                      : s.block,
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
                  enabled: !locked,
                  icon: const Icon(
                    Icons.more_vert,
                    size: 18,
                    color: AtShieldColors.muted,
                  ),
                  color: AtShieldColors.surface2,
                  onSelected: (v) {
                    if (v == 'delete') onDelete?.call();
                    if (v == 'toggle') onToggle?.call(!site.enabled);
                  },
                  itemBuilder: (_) => [
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
    );
  }
}

class SiteProperties extends StatefulWidget {
  const SiteProperties({
    super.key,
    required this.site,
    this.locked = false,
  });

  final SiteRule site;
  final bool locked;

  @override
  State<SiteProperties> createState() => _SitePropertiesState();
}

class _SitePropertiesState extends State<SiteProperties> {
  late TextEditingController _domain;
  late TextEditingController _page;
  bool _subdomains = true;
  bool _http = false;
  bool _https = true;
  bool _enabled = true;
  RedirectTarget _redirect = RedirectTarget.customPage;

  @override
  void initState() {
    super.initState();
    _domain = TextEditingController();
    _page = TextEditingController(text: 'foco.html');
    _sync(widget.site);
  }

  @override
  void didUpdateWidget(covariant SiteProperties oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site.id != widget.site.id) _sync(widget.site);
  }

  void _sync(SiteRule s) {
    _domain.text = s.domain;
    _page.text = s.pageFile;
    _subdomains = s.includeSubdomains;
    _http = s.http;
    _https = s.https;
    _enabled = s.enabled;
    _redirect = s.redirect;
  }

  @override
  void dispose() {
    _domain.dispose();
    _page.dispose();
    super.dispose();
  }

  InputDecoration get _input => const InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      );

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
    }
  }

  void _save() {
    if (widget.locked) return;
    final page = _page.text.trim();
    if (page.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.specifyHtmlFile)),
      );
      return;
    }
    final site = widget.site;
    context.read<ShieldCubit>().saveSite(
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
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final locked = widget.locked;
    return Material(
      color: AtShieldColors.surface,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.45),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AtShieldColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          border: Border(
            top: BorderSide(
              color: AtShieldColors.border.withValues(alpha: 0.8),
            ),
          ),
        ),
        child: CustomScrollView(
          shrinkWrap: true,
          primary: false,
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              sliver: SliverToBoxAdapter(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AtShieldColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (locked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    s.sitePropertiesReadonly,
                    style: TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 12,
                    ),
                  ),
                ),
              Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AtShieldColors.surface2,
                    child: Text(
                      site.domain[0].toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          site.domain,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            letterSpacing: -0.2,
                          ),
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
                  Text(
                    _enabled ? s.active : s.inactive,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _enabled
                          ? AtShieldColors.accent
                          : AtShieldColors.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AtToggle(
                    value: _enabled,
                    onChanged: locked
                        ? null
                        : (v) => setState(() => _enabled = v),
                  ),
                  IconButton(
                    tooltip: s.close,
                    onPressed: () =>
                        context.read<ShieldCubit>().clearSiteSelection(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AtShieldColors.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AtShieldColors.border),
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _field(
                            s.domain,
                            TextField(
                              controller: _domain,
                              enabled: !locked,
                              decoration: _input,
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
                              dropdownColor: AtShieldColors.surface,
                              decoration: _input,
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
                        const SizedBox(width: 12),
                        Expanded(
                          child: _field(
                            s.redirect,
                            DropdownButtonFormField<RedirectTarget>(
                              initialValue: _redirect,
                              isExpanded: true,
                              dropdownColor: AtShieldColors.surface,
                              decoration: _input,
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
                          flex: 2,
                          child: _field(
                            s.blockPage,
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _page,
                                    enabled: !locked,
                                    decoration: _input.copyWith(
                                      hintText: 'foco.html',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _iconAction(
                                  tooltip: s.browseHtml,
                                  icon: Icons.folder_open_outlined,
                                  onPressed: locked
                                      ? null
                                      : () async {
                                          final path = await pickHtmlFile();
                                          if (path != null && mounted) {
                                            setState(() => _page.text = path);
                                          }
                                        },
                                ),
                                const SizedBox(width: 4),
                                _iconAction(
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          s.protocols,
                          style: TextStyle(
                            fontSize: 10,
                            letterSpacing: 0.08,
                            color: AtShieldColors.muted,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilterChip(
                          label: const Text('http'),
                          selected: _http,
                          onSelected: locked
                              ? null
                              : (v) => setState(() => _http = v),
                          selectedColor:
                              AtShieldColors.accent.withValues(alpha: 0.25),
                          checkmarkColor: AtShieldColors.accent,
                          backgroundColor: AtShieldColors.surface,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: _http
                                ? AtShieldColors.accent
                                : AtShieldColors.border,
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('https'),
                          selected: _https,
                          onSelected: locked
                              ? null
                              : (v) => setState(() => _https = v),
                          selectedColor:
                              AtShieldColors.accent.withValues(alpha: 0.25),
                          checkmarkColor: AtShieldColors.accent,
                          backgroundColor: AtShieldColors.surface,
                          visualDensity: VisualDensity.compact,
                          side: BorderSide(
                            color: _https
                                ? AtShieldColors.accent
                                : AtShieldColors.border,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: locked ? null : _confirmDelete,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: Text(s.delete),
                    style: TextButton.styleFrom(
                      foregroundColor: AtShieldColors.muted,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () =>
                        context.read<ShieldCubit>().clearSiteSelection(),
                    child: Text(s.cancel),
                  ),
                  const SizedBox(width: 8),
                  AtRedButton(
                    label: s.saveChanges,
                    icon: Icons.check,
                    dense: true,
                    onPressed: locked ? null : _save,
                  ),
                ],
              ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconAction({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AtShieldColors.surface,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AtShieldColors.border),
            ),
            child: Icon(
              icon,
              size: 18,
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
            fontSize: 10,
            letterSpacing: 0.08,
            color: AtShieldColors.muted,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
