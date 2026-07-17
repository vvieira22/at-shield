import 'package:flutter/foundation.dart';

class Profile {
  Profile({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );
}

enum RedirectTarget { customPage, block }

class SiteRule {
  SiteRule({
    required this.id,
    required this.profileId,
    required this.domain,
    this.includeSubdomains = true,
    this.redirect = RedirectTarget.customPage,
    this.pageFile = 'foco.html',
    this.http = false,
    this.https = true,
    this.enabled = true,
  });

  final String id;
  final String profileId;
  final String domain;
  final bool includeSubdomains;
  final RedirectTarget redirect;
  final String pageFile;
  final bool http;
  final bool https;
  bool enabled;

  factory SiteRule.fromJson(Map<String, dynamic> j) => SiteRule(
        id: j['id'] as String,
        profileId: j['profile_id'] as String,
        domain: j['domain'] as String,
        includeSubdomains: j['include_subdomains'] as bool? ?? true,
        redirect: (j['redirect'] as String?) == 'block'
            ? RedirectTarget.block
            : RedirectTarget.customPage,
        pageFile: j['page_file'] as String? ?? 'foco.html',
        http: j['http'] as bool? ?? false,
        https: j['https'] as bool? ?? true,
        enabled: j['enabled'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'profile_id': profileId,
        'domain': domain,
        'include_subdomains': includeSubdomains,
        'redirect':
            redirect == RedirectTarget.block ? 'block' : 'custom_page',
        'page_file': pageFile,
        'http': http,
        'https': https,
        'enabled': enabled,
      };

  SiteRule copyWith({
    String? pageFile,
    bool? enabled,
    bool? includeSubdomains,
    RedirectTarget? redirect,
    bool? http,
    bool? https,
  }) =>
      SiteRule(
        id: id,
        profileId: profileId,
        domain: domain,
        includeSubdomains: includeSubdomains ?? this.includeSubdomains,
        redirect: redirect ?? this.redirect,
        pageFile: pageFile ?? this.pageFile,
        http: http ?? this.http,
        https: https ?? this.https,
        enabled: enabled ?? this.enabled,
      );
}

enum SessionState { idle, running, paused }

class FocusSession {
  FocusSession({
    required this.profileId,
    required this.profileName,
    required this.state,
    required this.remainingSecs,
    required this.durationSecs,
  });

  final String profileId;
  final String profileName;
  final SessionState state;
  final int remainingSecs;
  final int durationSecs;

  factory FocusSession.fromJson(Map<String, dynamic> j) {
    final s = j['state'] as String? ?? 'idle';
    return FocusSession(
      profileId: j['profile_id'] as String,
      profileName: j['profile_name'] as String,
      state: switch (s) {
        'running' => SessionState.running,
        'paused' => SessionState.paused,
        _ => SessionState.idle,
      },
      remainingSecs: (j['remaining_secs'] as num?)?.toInt() ?? 0,
      durationSecs: (j['duration_secs'] as num?)?.toInt() ?? 0,
    );
  }

  String get remainingLabel {
    final m = remainingSecs ~/ 60;
    final s = remainingSecs % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }
}

@immutable
class ShieldState {
  const ShieldState({
    this.connected = false,
    this.protectionActive = false,
    this.version = '1.0.0',
    this.profiles = const [],
    this.sites = const [],
    this.selectedSiteId,
    this.activeProfileId,
    this.session,
    this.query = '',
    this.error,
  });

  final bool connected;
  final bool protectionActive;
  final String version;
  final List<Profile> profiles;
  final List<SiteRule> sites;
  final String? selectedSiteId;
  final String? activeProfileId;
  final FocusSession? session;
  final String query;
  final String? error;

  SiteRule? get selectedSite {
    if (selectedSiteId == null) return null;
    for (final s in sites) {
      if (s.id == selectedSiteId) return s;
    }
    return null;
  }

  List<SiteRule> get filteredSites {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return sites;
    return sites.where((s) => s.domain.toLowerCase().contains(q)).toList();
  }

  ShieldState copyWith({
    bool? connected,
    bool? protectionActive,
    String? version,
    List<Profile>? profiles,
    List<SiteRule>? sites,
    String? selectedSiteId,
    bool clearSelected = false,
    String? activeProfileId,
    FocusSession? session,
    bool clearSession = false,
    String? query,
    String? error,
    bool clearError = false,
  }) =>
      ShieldState(
        connected: connected ?? this.connected,
        protectionActive: protectionActive ?? this.protectionActive,
        version: version ?? this.version,
        profiles: profiles ?? this.profiles,
        sites: sites ?? this.sites,
        selectedSiteId:
            clearSelected ? null : (selectedSiteId ?? this.selectedSiteId),
        activeProfileId: activeProfileId ?? this.activeProfileId,
        session: clearSession ? null : (session ?? this.session),
        query: query ?? this.query,
        error: clearError ? null : (error ?? this.error),
      );
}
