import 'dart:io';

import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine/pick_html.dart';
import '../l10n/locale_controller.dart';
import 'section_frame.dart';

class PagesPanel extends StatefulWidget {
  const PagesPanel({super.key});

  @override
  State<PagesPanel> createState() => _PagesPanelState();
}

class _PagesPanelState extends State<PagesPanel> {
  /// Extra HTML files under pages/ (builtins resolved in build via `s`).
  List<_PageEntry> _extra = const [];
  String? _picked;

  @override
  void initState() {
    super.initState();
    _scanPagesDir();
  }

  Future<void> _scanPagesDir() async {
    final found = <_PageEntry>[];
    final names = {'foco.html', 'detox.html'};
    for (final dir in _candidateDirs()) {
      if (!await dir.exists()) continue;
      await for (final e in dir.list()) {
        if (e is! File) continue;
        final name = e.uri.pathSegments.last;
        if (!name.toLowerCase().endsWith('.html')) continue;
        if (names.contains(name)) continue;
        names.add(name);
        found.add(_PageEntry(name: name, label: name, path: e.path));
      }
    }
    if (mounted) setState(() => _extra = found);
  }

  List<_PageEntry> get _pages => [
        _PageEntry(name: 'foco.html', label: s.foco, builtin: true),
        _PageEntry(name: 'detox.html', label: s.detox, builtin: true),
        ..._extra,
      ];

  List<Directory> _candidateDirs() {
    final out = <Directory>[];
    final cwd = Directory('pages');
    out.add(cwd);
    try {
      final exe = Platform.resolvedExecutable;
      final sibling = Directory(
        '${File(exe).parent.path}${Platform.pathSeparator}pages',
      );
      out.add(sibling);
    } catch (_) {}
    // repo layout when running flutter from apps/at_shield
    out.add(Directory('..${Platform.pathSeparator}..${Platform.pathSeparator}pages'));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return SectionFrame(
      title: s.navPaginas,
      subtitle: s.pagesSubtitle,
      actions: [
        AtRedButton(
          label: s.browseHtml,
          icon: Icons.folder_open,
          dense: true,
          ghost: true,
          onPressed: () async {
            final path = await pickHtmlFile();
            if (path == null || !mounted) return;
            setState(() => _picked = path);
            await openPagePreview(path);
          },
        ),
        const SizedBox(width: 8),
        AtRedButton(
          label: s.openPreview,
          icon: Icons.open_in_browser,
          dense: true,
          onPressed: () => openPagePreview('foco.html'),
        ),
      ],
      child: ListView(
        children: [
          ..._pages.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: SurfaceCard(
                  child: Row(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AtShieldColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.description_outlined,
                          color: AtShieldColors.muted,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              p.builtin
                                  ? '${s.builtin}${p.name}'
                                  : (p.path ?? p.name),
                              style: const TextStyle(
                                color: AtShieldColors.muted,
                                fontSize: 12,
                                fontFamily: 'Consolas',
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: s.copyName,
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: p.name));
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(s.siteCopied(p.name)),
                                backgroundColor: AtShieldColors.surface2,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy, size: 18),
                      ),
                      AtRedButton(
                        label: s.preview,
                        dense: true,
                        ghost: true,
                        onPressed: () =>
                            openPagePreview(p.path ?? p.name),
                      ),
                    ],
                  ),
                ),
              )),
          if (_picked != null) ...[
            const SizedBox(height: 8),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.lastPickedHtml,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _picked!,
                    style: const TextStyle(
                      fontFamily: 'Consolas',
                      fontSize: 12,
                      color: AtShieldColors.muted,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    s.lastPickedHint,
                    style: TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AtRedButton(
                        label: s.copyPath,
                        dense: true,
                        ghost: true,
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _picked!),
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      AtRedButton(
                        label: s.preview,
                        dense: true,
                        onPressed: () => openPagePreview(_picked!),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            s.pagesFootnote,
            style: TextStyle(color: AtShieldColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _PageEntry {
  const _PageEntry({
    required this.name,
    required this.label,
    this.path,
    this.builtin = false,
  });

  final String name;
  final String label;
  final String? path;
  final bool builtin;
}
