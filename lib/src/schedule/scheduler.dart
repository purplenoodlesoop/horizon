import "dart:async";
import "dart:io";

import "package:horizon/src/event/event.dart";
import "package:horizon/src/schedule/cron.dart";
import "package:horizon/src/schedule/schedule.dart";
import "package:mark/mark.dart";

const _scheduleLastFireSubdir = "_horizon/schedules/.lastfire";
const _scheduleFireCountSubdir = "_horizon/schedules/.firecount";

/// Per-tick scheduler state. Reads schedules from disk on each tick
/// (cheap; usually <100 entries; same pattern as capabilities), then
/// emits one synthetic event per due schedule. State the scheduler
/// keeps:
/// - `_horizon/schedules/.lastfire/<id>` — last-fire ISO timestamp
/// - `_horizon/schedules/.firecount/<id>` — fire count integer
///
/// Storing scheduler state inside the schedules dir keeps it out of
/// `_horizon/turns/` (which is for orchestrator turns, not for raw
/// scheduler bookkeeping). Hidden via the leading dot to keep
/// Obsidian's indexer happy.
class Scheduler {
  Scheduler({required this.vaultPath, required this.logger});

  final String vaultPath;
  final Logger logger;

  /// Drives the scheduler tick. Yields one event per due schedule.
  /// Sleeps `tickInterval` between ticks. Cancellation propagates
  /// through the underlying `await Future<void>.delayed`.
  Stream<ScheduleFire> tick({
    Duration tickInterval = const Duration(seconds: 30),
  }) async* {
    while (true) {
      try {
        for (final fire in await _due()) {
          yield fire;
        }
      } on Object catch (e, st) {
        logger.error("Scheduler tick error: $e", stackTrace: st);
      }
      await Future<void>.delayed(tickInterval);
    }
  }

  Future<List<ScheduleFire>> _due() async {
    final schedules = await LoadSchedules(
      vaultPath: vaultPath,
      onError: (path, error) =>
          logger.warning("Schedule $path: $error"),
    );
    final now = DateTime.now().toUtc();
    final fires = <ScheduleFire>[];
    for (final s in schedules) {
      final lastFire = _readLastFire(s.id);
      if (!_isDue(s.spec, lastFire, now)) {
        continue;
      }
      fires.add(ScheduleFire(schedule: s, firedAt: now));
    }
    return fires;
  }

  /// Records a fire — bumps fire count, optionally deletes the file
  /// when `expires_after` is reached.
  void recordFire(Schedule s, DateTime firedAt) {
    _writeLastFire(s.id, firedAt);
    final count = _readFireCount(s.id) + 1;
    _writeFireCount(s.id, count);
    final cap = s.expiresAfter ?? _defaultExpires(s.spec);
    if (cap != null && count >= cap) {
      logger.info(
        "Schedule ${s.id} reached expires_after=$cap, removing",
      );
      _deleteSchedule(s);
    }
  }

  bool _isDue(ScheduleSpec spec, DateTime? lastFire, DateTime now) =>
      switch (spec) {
        IntervalSpec(:final duration) => lastFire == null ||
            now.difference(lastFire) >= duration,
        OneShotSpec(:final fireAt) =>
            lastFire == null && !now.isBefore(fireAt),
        CronSpec(:final expr) => _cronDue(expr, lastFire, now),
      };

  bool _cronDue(CronExpression expr, DateTime? lastFire, DateTime now) {
    // After the last fire (or one minute ago, on first tick), is
    // there a cron-matching minute up to and including now? Walking
    // forward gives us the deterministic "fire once per match" shape
    // even if multiple ticks land in the same minute.
    final base = lastFire ?? now.subtract(const Duration(minutes: 1));
    final next = expr.nextFire(base);
    if (next == null) {
      return false;
    }
    return !next.isAfter(now);
  }

  int? _defaultExpires(ScheduleSpec spec) =>
      spec is OneShotSpec ? 1 : null;

  String _lastFirePath(String id) =>
      "$vaultPath/$_scheduleLastFireSubdir/$id";
  String _fireCountPath(String id) =>
      "$vaultPath/$_scheduleFireCountSubdir/$id";

  DateTime? _readLastFire(String id) {
    final f = File(_lastFirePath(id));
    if (!f.existsSync()) {
      return null;
    }
    final raw = f.readAsStringSync().trim();
    return DateTime.tryParse(raw)?.toUtc();
  }

  void _writeLastFire(String id, DateTime ts) {
    final f = File(_lastFirePath(id));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(ts.toUtc().toIso8601String());
  }

  int _readFireCount(String id) {
    final f = File(_fireCountPath(id));
    if (!f.existsSync()) {
      return 0;
    }
    return int.tryParse(f.readAsStringSync().trim()) ?? 0;
  }

  void _writeFireCount(String id, int count) {
    final f = File(_fireCountPath(id));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync("$count");
  }

  void _deleteSchedule(Schedule s) {
    final file = File(s.absolutePath);
    if (file.existsSync()) {
      file.deleteSync();
    }
    final lf = File(_lastFirePath(s.id));
    if (lf.existsSync()) {
      lf.deleteSync();
    }
    final fc = File(_fireCountPath(s.id));
    if (fc.existsSync()) {
      fc.deleteSync();
    }
  }
}

/// One scheduler-firing — a Schedule and the time it fired.
class ScheduleFire {
  const ScheduleFire({required this.schedule, required this.firedAt});
  final Schedule schedule;
  final DateTime firedAt;
}

/// Builds the synthetic Event the harness loop dispatches when an
/// agent-mode schedule fires. The body is folded into the event
/// content under `## Context`, mirroring how heartbeats route through
/// the existing centralized pipeline.
Event scheduleEvent(ScheduleFire fire) {
  final id = "schedule_${fire.schedule.id}_"
      "${fire.firedAt.toIso8601String().replaceAll(":", "-")}";
  final content = fire.schedule.body.isEmpty
      ? fire.schedule.prompt
      : "${fire.schedule.prompt}\n\n## Context\n${fire.schedule.body}";
  return Event(
    id: id,
    content: content,
    channel: ScheduleChannel((
      scheduleId: fire.schedule.id,
      deliver: _deliverTag(fire.schedule.deliver),
    )),
    timestamp: fire.firedAt,
  );
}

String _deliverTag(DeliverTarget t) => switch (t) {
      DeliverOrigin() => "origin",
      DeliverTelegram(:final chatId) => "telegram($chatId)",
      DeliverNone() => "none",
    };

/// Parses the deliver tag back into a `DeliverTarget`. Mirror of
/// `_deliverTag` above.
DeliverTarget parseDeliverTag(String tag) {
  if (tag == "origin") {
    return const DeliverOrigin();
  }
  if (tag == "none") {
    return const DeliverNone();
  }
  final m = RegExp(r"^telegram\(\s*([^)]+)\s*\)$").firstMatch(tag);
  if (m != null) {
    return DeliverTelegram(m.group(1)!.trim());
  }
  return const DeliverOrigin();
}
