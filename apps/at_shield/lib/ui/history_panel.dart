import 'package:at_shield_ui/at_shield_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../engine/models.dart';
import '../engine/shield_cubit.dart';
import '../l10n/locale_controller.dart';
import 'section_frame.dart';
import 'session_summary_dialog.dart';

class HistoryPanel extends StatefulWidget {
  const HistoryPanel({super.key});

  @override
  State<HistoryPanel> createState() => _HistoryPanelState();
}

class _HistoryPanelState extends State<HistoryPanel> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<ShieldCubit>().loadSessionHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ShieldCubit, ShieldState>(
      builder: (context, state) {
        final byDay = _groupByDay(state.sessionHistory);
        return SectionFrame(
          title: s.history,
          subtitle: s.historySubtitle,
          actions: [
            AtRedButton(
              label: s.clear,
              icon: Icons.delete_outline,
              dense: true,
              outlined: true,
              onPressed: state.sessionHistory.isEmpty
                  ? null
                  : () => _confirmClear(context),
            ),
          ],
          child: byDay.isEmpty
              ? Center(
                  child: Text(
                    s.historyEmpty,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AtShieldColors.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: byDay.length,
                  itemBuilder: (context, i) {
                    final day = byDay[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.protectionDay(day.label),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              letterSpacing: 0.02,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...day.records.map(
                            (r) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _HistoryCard(record: r),
                            ),
                          ),
                        ],
                      ),
                    );
              },
            ),
        );
      },
    );
  }

  Future<void> _confirmClear(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AtShieldColors.surface,
        title: Text(s.clearHistoryTitle),
        content: Text(s.clearHistoryContent),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          AtRedButton(
            label: s.clear,
            dense: true,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await context.read<ShieldCubit>().clearSessionHistory();
  }
}

class _DayGroup {
  _DayGroup({required this.label, required this.records});
  final String label;
  final List<SessionRecord> records;
}

List<_DayGroup> _groupByDay(List<SessionRecord> all) {
  final map = <String, List<SessionRecord>>{};
  final order = <String>[];
  for (final r in all) {
    final key = r.dateLabel;
    if (!map.containsKey(key)) {
      map[key] = [];
      order.add(key);
    }
    map[key]!.add(r);
  }
  return order
      .map((k) => _DayGroup(label: k, records: map[k]!))
      .toList();
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final SessionRecord record;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => showSessionSummaryDialog(context, record),
        child: SurfaceCard(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.profileName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      record.timeRangeLabel,
                      style: const TextStyle(
                        color: AtShieldColors.muted,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      record.reasonLabel,
                      style: const TextStyle(
                        color: AtShieldColors.muted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${record.totalAttempts}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: AtShieldColors.accent,
                    ),
                  ),
                  Text(
                    s.attemptsLabel(record.totalAttempts),
                    style: const TextStyle(
                      color: AtShieldColors.muted,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                color: AtShieldColors.muted,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
