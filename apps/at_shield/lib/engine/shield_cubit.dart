import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import 'models.dart';
import 'shield_rpc.dart';

class ShieldCubit extends Cubit<ShieldState> {
  ShieldCubit({ShieldRpc? rpc})
      : _rpc = rpc ?? ShieldRpc(),
        super(const ShieldState());

  final ShieldRpc _rpc;
  Timer? _sessionTick;
  Timer? _reconnect;

  Future<void> boot() async {
    _reconnect?.cancel();
    final ok = await _rpc.connect(timeout: const Duration(seconds: 2));
    if (!ok) {
      emit(state.copyWith(
        connected: false,
        error:
            'Serviço offline — rode scripts\\dev-windows.bat (deixe a janela preta aberta)',
      ));
      _reconnect = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (isClosed || state.connected) return;
        final c = await _rpc.connect(timeout: const Duration(seconds: 2));
        if (c) {
          await refresh();
          _startSessionTick();
        }
      });
      return;
    }
    await refresh();
    _startSessionTick();
  }

  void _startSessionTick() {
    _sessionTick?.cancel();
    _sessionTick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.session?.state == SessionState.running) {
        unawaited(_pullSession());
      }
    });
  }

  Future<void> refresh() async {
    try {
      final health = await _rpc.call({'cmd': 'health'});
      if (_ok(health) == 'error') {
        emit(state.copyWith(
          connected: false,
          error: _err(health),
        ));
        return;
      }
      final profiles = await _rpc.call({'cmd': 'list_profiles'});
      final profileId = state.activeProfileId ??
          _firstProfileId(profiles) ??
          'profile-trabalho';
      final sites = await _rpc.call({
        'cmd': 'list_sites',
        'profile_id': profileId,
      });
      final session = await _rpc.call({'cmd': 'get_session'});
      final list = _parseSites(sites);
      final sel = state.selectedSiteId;
      final validSel = (sel != null && list.any((s) => s.id == sel))
          ? sel
          : (list.isNotEmpty ? list.first.id : null);

      emit(state.copyWith(
        connected: true,
        clearError: true,
        protectionActive: _data(health)?['protection_active'] as bool? ?? false,
        version: _data(health)?['version'] as String? ?? state.version,
        profiles: _parseProfiles(profiles),
        sites: list,
        activeProfileId: profileId,
        session: _parseSession(session),
        clearSession: _ok(session) == 'session' && _dataRaw(session) == null,
        selectedSiteId: validSel,
        clearSelected: validSel == null,
      ));
    } catch (e) {
      emit(state.copyWith(
        connected: false,
        error: 'Falha ao falar com o serviço',
      ));
    }
  }

  Future<void> selectProfile(String id) async {
    emit(state.copyWith(activeProfileId: id));
    final sites = await _rpc.call({'cmd': 'list_sites', 'profile_id': id});
    final list = _parseSites(sites);
    emit(state.copyWith(
      sites: list,
      selectedSiteId: list.isNotEmpty ? list.first.id : null,
      clearSelected: list.isEmpty,
    ));
  }

  void selectSite(String id) => emit(state.copyWith(selectedSiteId: id));

  void setQuery(String q) => emit(state.copyWith(query: q));

  Future<void> toggleSite(String id, bool enabled) async {
    final resp = await _rpc.call({
      'cmd': 'set_enabled',
      'id': id,
      'enabled': enabled,
    });
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    // reload — aliases (x.com/twitter.com) may have flipped too
    await refresh();
    await _refreshHealth();
  }

  Future<void> toggleAll(bool enabled) async {
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
    final resp = await _rpc.call({'cmd': 'upsert_site', 'site': site.toJson()});
    // Always reload — DB may have written even when filter sync failed.
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

  /// Returns true when the domain already exists in the active profile list.
  SiteRule? findSiteByDomain(String domain) {
    final d = domain.trim().toLowerCase();
    for (final s in state.sites) {
      if (s.domain == d) return s;
    }
    return null;
  }

  Future<void> deleteSite(String id) async {
    final resp = await _rpc.call({'cmd': 'delete_site', 'id': id});
    if (_ok(resp) == 'error') {
      emit(state.copyWith(error: _err(resp)));
      return;
    }
    await refresh();
    emit(state.copyWith(clearError: true));
  }

  Future<void> startSession({int durationSecs = 45 * 60}) async {
    final pid = state.activeProfileId;
    if (pid == null) return;
    await _rpc.call({
      'cmd': 'start_session',
      'profile_id': pid,
      'duration_secs': durationSecs,
    });
    await refresh();
  }

  Future<void> pauseSession() async {
    await _rpc.call({'cmd': 'pause_session'});
    await refresh();
  }

  Future<void> resumeSession() async {
    await _rpc.call({'cmd': 'resume_session'});
    await refresh();
  }

  Future<void> endSession() async {
    await _rpc.call({'cmd': 'end_session'});
    await refresh();
  }

  Future<void> _pullSession() async {
    final session = await _rpc.call({'cmd': 'get_session'});
    emit(state.copyWith(
      session: _parseSession(session),
      clearSession: _dataRaw(session) == null,
    ));
  }

  Future<void> _refreshHealth() async {
    final health = await _rpc.call({'cmd': 'health'});
    emit(state.copyWith(
      protectionActive: _data(health)?['protection_active'] as bool? ?? false,
    ));
  }

  @override
  Future<void> close() async {
    _sessionTick?.cancel();
    _reconnect?.cancel();
    await _rpc.close();
    return super.close();
  }

  static String? _ok(Map<String, dynamic> r) => r['ok'] as String?;
  static dynamic _dataRaw(Map<String, dynamic> r) => r['data'];
  static Map<String, dynamic>? _data(Map<String, dynamic> r) {
    final d = r['data'];
    return d is Map<String, dynamic> ? d : null;
  }

  static String _err(Map<String, dynamic> r) =>
      _data(r)?['message'] as String? ?? 'erro';

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
    final d = r['data'];
    if (d is Map<String, dynamic>) return FocusSession.fromJson(d);
    return null;
  }
}
