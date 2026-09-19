import 'dart:async';
import 'dart:io' show pid;

import 'package:flutter_bloc/flutter_bloc.dart';

import '../l10n/locale_controller.dart';
import 'local_prefs.dart';
import 'models.dart';
import 'shield_rpc.dart';

class ShieldCubit extends Cubit<ShieldState> {
  ShieldCubit({ShieldRpc? rpc})
      : _rpc = rpc ?? ShieldRpc(),
        super(const ShieldState());

  final ShieldRpc _rpc;
  Timer? _sessionTick;
  Timer? _reconnect;
  Timer? _healthTick;
  LocalPrefs? _prefs;

  LocalPrefs? get prefs => _prefs;
  bool get minimizeToTray => _prefs?.minimizeToTray ?? false;

  Future<void> boot() async {
    _reconnect?.cancel();
    _healthTick?.cancel();
    _prefs ??= await LocalPrefs.open();
    emit(state.copyWith(sessionDurationMins: _prefs!.sessionDurationMins));
    final ok = await _rpc.connect(timeout: const Duration(seconds: 2));
    if (!ok) {
      emit(state.copyWith(
        connected: false,
        error: s.serviceOfflineLong,
      ));
      _reconnect = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (isClosed || state.connected) return;
        final c = await _rpc.connect(timeout: const Duration(seconds: 2));
        if (c) {
          await refresh();
          _startTicks();
        }
      });
      return;
    }
    await refresh();
    _startTicks();
    // warm_protection is async on the service — re-poll health shortly after
    Future<void>.delayed(const Duration(seconds: 1), () {
      if (!isClosed) unawaited(_refreshHealth());
    });
    Future<void>.delayed(const Duration(seconds: 3), () {
      if (!isClosed) unawaited(_refreshHealth());
    });
  }

  void _startTicks() {
    _sessionTick?.cancel();
    _healthTick?.cancel();
    _sessionTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.session?.state == SessionState.running) {
        unawaited(_pullSession());
      }
    });
    _healthTick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (state.connected) unawaited(_refreshHealth());
    });
  }

  Future<Map<String, dynamic>> _health() =>
      _rpc.call({'cmd': 'health', 'ui_pid': pid});

  Future<void> refresh() async {
    try {
      final health = await _health();
      if (_ok(health) == 'error') {
        emit(state.copyWith(
          connected: false,
          error: _err(health),
        ));
        return;
      }
      final profiles = await _rpc.call({'cmd': 'list_profiles'});
      if (_ok(profiles) == 'error') {
        emit(state.copyWith(connected: true, error: _err(profiles)));
        return;
      }
      final profileId = state.activeProfileId ??
          _firstProfileId(profiles) ??
          'profile-estudo';
      final sites = await _rpc.call({
        'cmd': 'list_sites',
        'profile_id': profileId,
      });
      if (_ok(sites) == 'error') {
        emit(state.copyWith(connected: true, error: _err(sites)));
        return;
      }
      final allSites = await _rpc.call({
        'cmd': 'list_sites',
        'profile_id': null,
      });
      final session = await _rpc.call({'cmd': 'get_session'});
      final interrupted = await _rpc.call({'cmd': 'get_interrupted_session'});
      final list = _parseSites(sites);
      final sel = state.selectedSiteId;
      final validSel =
          (sel != null && list.any((s) => s.id == sel)) ? sel : null;
      final h = _data(health);
      final parked = _parseInterrupted(interrupted);

      emit(state.copyWith(
        connected: true,
        clearError: true,
        protectionActive: h?['protection_active'] as bool? ?? false,
        networkArmed: h?['network_armed'] as bool? ?? false,
        sessionActive: h?['session_active'] as bool? ?? false,
        enabledSitesTotal: (h?['enabled_sites'] as num?)?.toInt() ?? 0,
        version: h?['version'] as String? ?? state.version,
        profiles: _parseProfiles(profiles),
        sites: list,
        profileStats: _ok(allSites) == 'error'
            ? state.profileStats
            : _statsByProfile(_parseSites(allSites)),
        activeProfileId: profileId,
        session: _parseSession(session),
        clearSession: _ok(session) == 'session' && _dataRaw(session) == null,
        selectedSiteId: validSel,
        clearSelected: validSel == null,
        interruptedSession: parked,
        clearInterrupted: parked == null,
      ));
    } catch (e) {
      emit(state.copyWith(
        connected: false,
        error: s.failTalkService,
      ));
    }
  }

  Future<void> selectProfile(String id) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToSwitchProfile));
      return;
    }
    emit(state.copyWith(activeProfileId: id));
    if (!state.connected) return;
    final sites = await _rpc.call({'cmd': 'list_sites', 'profile_id': id});
    if (_ok(sites) == 'error') {
      // keep previous list — don't wipe on flaky IPC
      emit(state.copyWith(error: _err(sites)));
      return;
    }
    final list = _parseSites(sites);
    emit(state.copyWith(
      sites: list,
      clearSelected: true,
      clearError: true,
    ));
  }

  void selectSite(String id) => emit(state.copyWith(selectedSiteId: id));

  void clearSiteSelection() => emit(state.copyWith(clearSelected: true));

  void setQuery(String q) => emit(state.copyWith(query: q));

  Future<void> saveProfile(Profile profile) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEdit));
      return;
    }
    final resp = await _rpc.call({
      'cmd': 'upsert_profile',
      'profile': profile.toJson(),
    });
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    await refresh();
  }

  Future<void> deleteProfile(String id) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEdit));
      return;
    }
    final resp = await _rpc.call({'cmd': 'delete_profile', 'id': id});
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    if (state.activeProfileId == id) {
      emit(state.copyWith(activeProfileId: null));
    }
    await refresh();
  }

  Future<void> duplicateProfile(Profile source) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEdit));
      return;
    }
    final sitesResp = await _rpc.call({
      'cmd': 'list_sites',
      'profile_id': source.id,
    });
    final sites = _parseSites(sitesResp);
    final newId = 'profile-${DateTime.now().millisecondsSinceEpoch}';
    final copy = Profile(
      id: newId,
      name: '${source.name}${s.copySuffix}',
      sortOrder: state.profiles.length,
    );
    final up = await _rpc.call({
      'cmd': 'upsert_profile',
      'profile': copy.toJson(),
    });
    if (_ok(up) == 'error') {
      emit(state.copyWith(error: _err(up)));
      return;
    }
    for (final s in sites) {
      final cloned = s.copyWith(
        id: 'site-${DateTime.now().microsecondsSinceEpoch}-${s.domain}',
        profileId: newId,
      );
      await _rpc.call({'cmd': 'upsert_site', 'site': cloned.toJson()});
    }
    await selectProfile(newId);
    await refresh();
  }

  Future<void> applyProfile(String id) async {
    // Blocks only via start_session now.
    await startSession(profileId: id);
  }

  Future<void> setProfileSitesEnabled(String profileId, bool enabled) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEditSites));
      return;
    }
    final wasActive = state.activeProfileId == profileId;
    if (!wasActive) {
      final sites = await _rpc.call({
        'cmd': 'list_sites',
        'profile_id': profileId,
      });
      if (_ok(sites) == 'error') {
        emit(state.copyWith(error: _err(sites)));
        return;
      }
      final list = _parseSites(sites);
      if (list.isEmpty) return;
      final resp = await _rpc.call({
        'cmd': 'set_enabled_batch',
        'ids': list.map((s) => s.id).toList(),
        'enabled': enabled,
      });
      if (_ok(resp) == 'error') {
        emit(state.copyWith(error: _err(resp)));
        return;
      }
    } else {
      await toggleAll(enabled);
      return;
    }
    await refresh();
  }

  Future<void> toggleSite(String id, bool enabled) async {
    if (!state.connected) {
      emit(state.copyWith(error: s.serviceOffline));
      return;
    }
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEditSites));
      return;
    }
    final resp = await _rpc.call({
      'cmd': 'set_enabled',
      'id': id,
      'enabled': enabled,
    });
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    await refresh();
  }

  Future<void> toggleAll(bool enabled) async {
    if (!state.connected) {
      emit(state.copyWith(error: s.serviceOffline));
      return;
    }
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEditSites));
      return;
    }
    final ids = state.sites.map((s) => s.id).toList();
    final resp = await _rpc.call({
      'cmd': 'set_enabled_batch',
      'ids': ids,
      'enabled': enabled,
    });
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    await refresh();
  }

  Future<void> saveSite(SiteRule site) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEditSites));
      return;
    }
    final resp = await _rpc.call({'cmd': 'upsert_site', 'site': site.toJson()});
    await refresh();
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    final saved =
        _data(resp) != null ? SiteRule.fromJson(_data(resp)!) : site;
    emit(state.copyWith(
      selectedSiteId: saved.id,
      query: '',
      clearError: true,
    ));
  }

  SiteRule? findSiteByDomain(String domain) {
    final d = domain.trim().toLowerCase();
    for (final s in state.sites) {
      if (s.domain == d) return s;
    }
    return null;
  }

  Future<void> deleteSite(String id) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToEditSites));
      return;
    }
    final resp = await _rpc.call({'cmd': 'delete_site', 'id': id});
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    await refresh();
    emit(state.copyWith(clearError: true));
  }

  Future<void> setSessionDurationMins(int mins) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.endSessionToChangeDuration));
      return;
    }
    final v = mins.clamp(1, 24 * 60);
    emit(state.copyWith(sessionDurationMins: v));
    _prefs ??= await LocalPrefs.open();
    await _prefs!.setSessionDurationMins(v);
  }

  Future<void> startSession({
    String? profileId,
    int? durationSecs,
  }) async {
    if (state.editingLocked) {
      emit(state.copyWith(error: s.alreadyHasSession));
      return;
    }
    final pid = profileId ?? state.activeProfileId;
    if (pid == null) return;
    if (pid != state.activeProfileId) {
      await selectProfile(pid);
    }
    final secs = durationSecs ?? state.sessionDurationSecs;
    final resp = await _rpc.call({
      'cmd': 'start_session',
      'profile_id': pid,
      'duration_secs': secs,
    });
    await refresh();
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    if (!state.networkArmed) {
      emit(state.copyWith(
        error: s.sessionOkNeedsAdmin,
      ));
    }
  }

  Future<void> endSession() async {
    // Drop local session first so the tick won't race-pop the summary.
    emit(state.copyWith(clearSession: true, sessionActive: false));
    final resp = await _rpc.call({'cmd': 'end_session'});
    SessionRecord? summary;
    if (_ok(resp) == 'session_summary') {
      final d = _data(resp);
      if (d != null) summary = SessionRecord.fromJson(d);
    }
    await refresh();
    if (summary != null) {
      emit(state.copyWith(lastSummary: summary));
      unawaited(loadSessionHistory());
    }
  }

  void clearLastSummary() => emit(state.copyWith(clearLastSummary: true));

  Future<void> restoreInterruptedSession() async {
    final resp = await _rpc.call({'cmd': 'restore_interrupted_session'});
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp), clearInterrupted: true));
      return;
    }
    await refresh();
  }

  Future<void> discardInterruptedSession() async {
    await _rpc.call({'cmd': 'discard_interrupted_session'});
    emit(state.copyWith(clearInterrupted: true));
  }

  Future<void> loadSessionHistory() async {
    if (!state.connected) return;
    final resp = await _rpc.call({'cmd': 'list_session_history'});
    if (_ok(resp) == 'error') return;
    final d = _dataRaw(resp);
    if (d is! List) return;
    final list = d
        .whereType<Map<String, dynamic>>()
        .map(SessionRecord.fromJson)
        .toList();
    emit(state.copyWith(sessionHistory: list));
  }

  Future<void> clearSessionHistory() async {
    if (!state.connected) return;
    final resp = await _rpc.call({'cmd': 'clear_session_history'});
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    emit(state.copyWith(sessionHistory: const [], clearError: true));
  }

  Future<void> _pullSession() async {
    final hadSession = state.session != null;
    final session = await _rpc.call({'cmd': 'get_session'});
    final nowNull = _dataRaw(session) == null;
    emit(state.copyWith(
      session: _parseSession(session),
      clearSession: nowNull,
      sessionActive: !nowNull,
    ));
    // Timer auto-end → pop summary for dialog
    if (hadSession && nowNull) {
      final pop = await _rpc.call({'cmd': 'pop_session_summary'});
      if (_ok(pop) == 'session_summary') {
        final d = _data(pop);
        if (d != null) {
          emit(state.copyWith(lastSummary: SessionRecord.fromJson(d)));
          unawaited(loadSessionHistory());
        }
      }
    }
  }

  Future<void> _refreshHealth() async {
    final health = await _health();
    if (_ok(health) == 'error') return;
    final h = _data(health);
    emit(state.copyWith(
      protectionActive: h?['protection_active'] as bool? ?? false,
      networkArmed: h?['network_armed'] as bool? ?? false,
      sessionActive: h?['session_active'] as bool? ?? false,
      enabledSitesTotal: (h?['enabled_sites'] as num?)?.toInt() ?? 0,
    ));
  }

  /// Drop protection before the UI process exits (quit / taskbar close / tray Sair).
  Future<void> disarmForQuit() async {
    _sessionTick?.cancel();
    _healthTick?.cancel();
    try {
      await _rpc
          .call({'cmd': 'end_session'})
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  Future<void> close() async {
    _sessionTick?.cancel();
    _healthTick?.cancel();
    _reconnect?.cancel();
    // Fechar a UI não pode deixar o serviço armado com sessão viva.
    await disarmForQuit();
    await _rpc.close();
    return super.close();
  }

  static Map<String, ProfileStats> _statsByProfile(List<SiteRule> sites) {
    final map = <String, ProfileStats>{};
    for (final s in sites) {
      final cur = map[s.profileId] ?? const ProfileStats();
      map[s.profileId] = ProfileStats(
        total: cur.total + 1,
        enabled: cur.enabled + (s.enabled ? 1 : 0),
      );
    }
    return map;
  }

  static String? _ok(Map<String, dynamic> r) => r['ok'] as String?;
  static dynamic _dataRaw(Map<String, dynamic> r) => r['data'];
  static Map<String, dynamic>? _data(Map<String, dynamic> r) {
    final d = r['data'];
    return d is Map<String, dynamic> ? d : null;
  }

  static String _err(Map<String, dynamic> r) {
    final msg = _data(r)?['message'] as String? ?? s.error;
    if (LocaleController.instance.lang != AppLang.en) return msg;
    // ponytail: service speaks PT — map known msgs; new ones stay as-is until translated at source
    const map = {
      'encerre a sessão pra editar sites': 'End session to edit sites',
      'precisa de pelo menos um perfil': 'Need at least one profile',
      'bloqueio só via sessão — use iniciar sessão':
          'Blocking only via session — start a session',
      'já tem sessão ativa — encerre antes':
          'Session already active — end first',
    };
    for (final e in map.entries) {
      if (msg == e.key) return e.value;
      if (msg.contains(e.key)) return msg.replaceFirst(e.key, e.value);
    }
    return msg
        .replaceAll('precisa admin', 'needs Admin')
        .replaceAll('precisa Admin', 'needs Admin');
  }

  static String? _firstProfileId(Map<String, dynamic> r) {
    final list = _parseProfiles(r);
    return list.isEmpty ? null : list.first.id;
  }

  static List<Profile> _parseProfiles(Map<String, dynamic> r) {
    final d = r['data'];
    if (d is! List) return [];
    return d
        .whereType<Map<String, dynamic>>()
        .map(Profile.fromJson)
        .toList();
  }

  static List<SiteRule> _parseSites(Map<String, dynamic> r) {
    final d = r['data'];
    if (d is! List) return [];
    return d.whereType<Map<String, dynamic>>().map(SiteRule.fromJson).toList();
  }

  static FocusSession? _parseSession(Map<String, dynamic> r) {
    // Don't treat error/pong/etc maps as a session (no profile_id → crash).
    if (_ok(r) != 'session') return null;
    final d = r['data'];
    if (d is Map<String, dynamic>) return FocusSession.fromJson(d);
    return null;
  }

  static InterruptedSession? _parseInterrupted(Map<String, dynamic> r) {
    if (_ok(r) != 'interrupted_session') return null;
    final d = r['data'];
    if (d is Map<String, dynamic>) return InterruptedSession.fromJson(d);
    return null;
  }
}
