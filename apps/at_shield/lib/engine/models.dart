import 'package:flutter/foundation.dart';

import '../l10n/locale_controller.dart';

class Profile {
  Profile({required this.id, required this.name, this.sortOrder = 0});

  final String id;
  final String name;
  final int sortOrder;

  /// Built-in defaults — never deletable from the UI / engine.
  bool get isBuiltin =>
      id == 'profile-estudo' ||
      id == 'profile-detox-total' ||
      id == 'profile-adulto';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String,
        sortOrder: (j['sort_order'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
      };
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
    String? id,
    String? profileId,
    String? domain,
    String? pageFile,
    bool? enabled,
    bool? includeSubdomains,
    RedirectTarget? redirect,
    bool? http,
    bool? https,
  }) =>
      SiteRule(
        id: id ?? this.id,
        profileId: profileId ?? this.profileId,
        domain: domain ?? this.domain,
        includeSubdomains: includeSubdomains ?? this.includeSubdomains,
        redirect: redirect ?? this.redirect,
        pageFile: pageFile ?? this.pageFile,
        http: http ?? this.http,
        https: https ?? this.https,
        enabled: enabled ?? this.enabled,
      );
}

enum SessionState { idle, running }

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
      profileId: j['profile_id'] as String? ?? '',
      profileName: j['profile_name'] as String? ?? '',
      state: s == 'running' ? SessionState.running : SessionState.idle,
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

class DomainHit {
  DomainHit({required this.domain, required this.count});

  final String domain;
  final int count;

  factory DomainHit.fromJson(Map<String, dynamic> j) => DomainHit(
        domain: j['domain'] as String? ?? '',
        count: (j['count'] as num?)?.toInt() ?? 0,
      );
}

class SessionRecord {
  SessionRecord({
    required this.id,
    required this.profileId,
    required this.profileName,
    required this.startedAt,
    required this.endedAt,
    required this.durationSecs,
    required this.elapsedSecs,
    required this.endedReason,
    required this.totalAttempts,
    required this.attempts,
  });

  final String id;
  final String profileId;
  final String profileName;
  final int startedAt;
  final int endedAt;
  final int durationSecs;
  final int elapsedSecs;
  final String endedReason;
  final int totalAttempts;
  final List<DomainHit> attempts;

  factory SessionRecord.fromJson(Map<String, dynamic> j) {
    final raw = j['attempts'];
    final attempts = raw is List
        ? raw
            .whereType<Map<String, dynamic>>()
            .map(DomainHit.fromJson)
            .toList()
        : <DomainHit>[];
    return SessionRecord(
      id: j['id'] as String? ?? '',
      profileId: j['profile_id'] as String? ?? '',
      profileName: j['profile_name'] as String? ?? '',
      startedAt: (j['started_at'] as num?)?.toInt() ?? 0,
      endedAt: (j['ended_at'] as num?)?.toInt() ?? 0,
      durationSecs: (j['duration_secs'] as num?)?.toInt() ?? 0,
      elapsedSecs: (j['elapsed_secs'] as num?)?.toInt() ?? 0,
      endedReason: j['ended_reason'] as String? ?? 'manual',
      totalAttempts: (j['total_attempts'] as num?)?.toInt() ?? 0,
      attempts: attempts,
    );
  }

  DateTime get startedLocal =>
      DateTime.fromMillisecondsSinceEpoch(startedAt * 1000);
  DateTime get endedLocal =>
      DateTime.fromMillisecondsSinceEpoch(endedAt * 1000);

  String get dateLabel {
    final d = startedLocal;
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year}';
  }

  String get timeRangeLabel {
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${hm(startedLocal)} – ${hm(endedLocal)}';
  }

  String get reasonLabel =>
      endedReason == 'timer' ? s.reasonTimer : s.reasonManual;
}

@immutable
class ProfileStats {
  const ProfileStats({this.total = 0, this.enabled = 0});
  final int total;
  final int enabled;
}

@immutable
class ShieldState {
  const ShieldState({
    this.connected = false,
    this.protectionActive = false,
    this.networkArmed = false,
    this.sessionActive = false,
    this.enabledSitesTotal = 0,
    this.version = '1.0.0',
    this.profiles = const [],
    this.sites = const [],
    this.profileStats = const {},
    this.selectedSiteId,
    this.activeProfileId,
    this.session,
    this.query = '',
    this.error,
    this.lastSummary,
    this.sessionHistory = const [],
    this.sessionDurationMins = 15,
  });

  final bool connected;
  final bool protectionActive;
  /// WFP/hosts applied for real (false = precisa Admin).
  final bool networkArmed;
  final bool sessionActive;
  final int enabledSitesTotal;
  final String version;
  final List<Profile> profiles;
  final List<SiteRule> sites;
  final Map<String, ProfileStats> profileStats;
  final String? selectedSiteId;
  final String? activeProfileId;
  final FocusSession? session;
  final String query;
  final String? error;
  /// Set when a session ends — UI shows summary then clears.
  final SessionRecord? lastSummary;
  final List<SessionRecord> sessionHistory;
  /// Planned duration when starting the next session.
  final int sessionDurationMins;

  int get sessionDurationSecs => sessionDurationMins * 60;

  SiteRule? get selectedSite {
    if (selectedSiteId == null) return null;
    for (final s in sites) {
      if (s.id == selectedSiteId) return s;
    }
    return null;
  }

  /// Sessão ligada = não dá pra marcar/editar sites.
  bool get editingLocked => session != null;

  List<SiteRule> get filteredSites {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return sites;
    return sites.where((s) => s.domain.toLowerCase().contains(q)).toList();
  }

  ShieldState copyWith({
    bool? connected,
    bool? protectionActive,
    bool? networkArmed,
    bool? sessionActive,
    int? enabledSitesTotal,
    String? version,
    List<Profile>? profiles,
    List<SiteRule>? sites,
    Map<String, ProfileStats>? profileStats,
    String? selectedSiteId,
    bool clearSelected = false,
    String? activeProfileId,
    FocusSession? session,
    bool clearSession = false,
    String? query,
    String? error,
    bool clearError = false,
    SessionRecord? lastSummary,
    bool clearLastSummary = false,
    List<SessionRecord>? sessionHistory,
    int? sessionDurationMins,
  }) =>
      ShieldState(
        connected: connected ?? this.connected,
        protectionActive: protectionActive ?? this.protectionActive,
        networkArmed: networkArmed ?? this.networkArmed,
        sessionActive: sessionActive ?? this.sessionActive,
        enabledSitesTotal: enabledSitesTotal ?? this.enabledSitesTotal,
        version: version ?? this.version,
        profiles: profiles ?? this.profiles,
        sites: sites ?? this.sites,
        profileStats: profileStats ?? this.profileStats,
        selectedSiteId:
            clearSelected ? null : (selectedSiteId ?? this.selectedSiteId),
        activeProfileId: activeProfileId ?? this.activeProfileId,
        session: clearSession ? null : (session ?? this.session),
        query: query ?? this.query,
        error: clearError ? null : (error ?? this.error),
        lastSummary:
            clearLastSummary ? null : (lastSummary ?? this.lastSummary),
        sessionHistory: sessionHistory ?? this.sessionHistory,
        sessionDurationMins: sessionDurationMins ?? this.sessionDurationMins,
      );
}
