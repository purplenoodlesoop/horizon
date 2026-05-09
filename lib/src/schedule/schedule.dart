import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/capability/schedule.dart" show parseSchedule;
import "package:horizon/src/schedule/cron.dart";
import "package:yaml/yaml.dart";

const schedulesSubdir = "_horizon/schedules";

/// A single user- or agent-authored schedule entry. Lives at
/// `<vault>/_horizon/schedules/<id>.md`.
class Schedule {
  const Schedule({
    required this.id,
    required this.prompt,
    required this.spec,
    required this.deliver,
    required this.createdBy,
    required this.expiresAfter,
    required this.noAgent,
    required this.body,
    required this.relativePath,
    required this.absolutePath,
  });

  final String id;
  final String prompt;
  final ScheduleSpec spec;
  final DeliverTarget deliver;

  /// `user` or `agent` — recorded only; affects nothing today.
  final String createdBy;

  /// Optional fire-count cap. After this many fires, the file is
  /// deleted by the scheduler. Default: 1 for one-shot, unbounded for
  /// recurring. `null` = unbounded.
  final int? expiresAfter;

  /// When true, the entry is a watchdog: `prompt` is reinterpreted as
  /// `<tool_name> <arg1> <arg2>...` and run through the executor with
  /// no LLM in the loop. See spec/phase-7-plan.md §7.4.
  final bool noAgent;

  final String body;
  final String relativePath;
  final String absolutePath;
}

sealed class ScheduleSpec {
  const ScheduleSpec();
}

final class IntervalSpec extends ScheduleSpec {
  const IntervalSpec(this.duration);
  final Duration duration;
}

final class CronSpec extends ScheduleSpec {
  const CronSpec(this.expr);
  final CronExpression expr;
}

final class OneShotSpec extends ScheduleSpec {
  const OneShotSpec(this.fireAt);
  final DateTime fireAt;
}

sealed class DeliverTarget {
  const DeliverTarget();
}

/// Reply goes back through the channel that created the schedule. For
/// agent-tool-created schedules, the calling chat_id is stamped into
/// the file at creation time so this resolves to a concrete chat.
final class DeliverOrigin extends DeliverTarget {
  const DeliverOrigin();
}

final class DeliverTelegram extends DeliverTarget {
  const DeliverTelegram(this.chatId);
  final String chatId;
}

/// Fire and forget — the reply (if any) is logged but not sent.
final class DeliverNone extends DeliverTarget {
  const DeliverNone();
}

/// Loads all schedule entries from `<vault>/_horizon/schedules/`.
///
/// Re-invoked by the scheduler tick so user/agent edits propagate
/// without restart. Malformed entries are logged and dropped from
/// the active set; the harness keeps running.
class LoadSchedules extends Fx<IList<Schedule>> {
  LoadSchedules({
    required String vaultPath,
    required void Function(String path, Object error) onError,
  }) : super(() {
          final dir = Directory("$vaultPath/$schedulesSubdir");
          if (!dir.existsSync()) {
            return IList();
          }
          final files = dir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.endsWith(".md"))
              .toList()
            ..sort((a, b) => a.path.compareTo(b.path));
          final schedules = <Schedule>[];
          for (final file in files) {
            try {
              final content = file.readAsStringSync();
              final s = _parseSchedule(file, vaultPath, content);
              if (s != null) {
                schedules.add(s);
              }
            } on Object catch (e) {
              onError(file.path, e);
            }
          }
          return schedules.toIList();
        });
}

Schedule? _parseSchedule(File file, String vaultPath, String content) {
  final normalized = content.replaceAll("\r\n", "\n");
  if (!normalized.startsWith("---\n")) {
    throw const FormatException("Schedule file missing frontmatter");
  }
  final lines = normalized.split("\n");
  var endIdx = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == "---") {
      endIdx = i;
      break;
    }
  }
  if (endIdx < 0) {
    throw const FormatException("Schedule frontmatter not closed");
  }
  final frontmatter = lines.sublist(1, endIdx).join("\n");
  final Object? doc = loadYaml(frontmatter);
  if (doc is! YamlMap) {
    throw const FormatException("Schedule frontmatter must be a YAML map");
  }
  final body = lines.sublist(endIdx + 1).join("\n").trim();
  final id = doc["id"];
  final prompt = doc["prompt"];
  final scheduleStr = doc["schedule"];
  if (id is! String || id.isEmpty) {
    throw const FormatException("Schedule missing required `id`");
  }
  if (prompt is! String || prompt.isEmpty) {
    throw const FormatException("Schedule missing required `prompt`");
  }
  if (scheduleStr is! String || scheduleStr.isEmpty) {
    throw const FormatException("Schedule missing required `schedule`");
  }
  final spec = _parseSpec(scheduleStr);
  final deliver = _parseDeliver(doc["deliver"]);
  final createdBy = doc["created_by"] is String
      ? doc["created_by"] as String
      : "user";
  final expiresRaw = doc["expires_after"];
  final expiresAfter = expiresRaw is int ? expiresRaw : null;
  final noAgentRaw = doc["no_agent"];
  final noAgent = noAgentRaw == true || noAgentRaw == "true";
  final prefix = "$vaultPath/";
  final relativePath = file.path.startsWith(prefix)
      ? file.path.substring(prefix.length)
      : file.path;
  if (noAgent && spec is IntervalSpec) {
    if (spec.duration < _noAgentMinInterval) {
      throw FormatException(
        "no_agent schedules must use intervals >= "
        "${_noAgentMinInterval.inSeconds}s; got ${spec.duration.inSeconds}s",
      );
    }
  }
  return Schedule(
    id: id,
    prompt: prompt,
    spec: spec,
    deliver: deliver,
    createdBy: createdBy,
    expiresAfter: expiresAfter,
    noAgent: noAgent,
    body: body,
    relativePath: relativePath,
    absolutePath: file.path,
  );
}

/// Minimum interval for `no_agent: true` schedules. Below this, the
/// subprocess startup cost dominates and the user almost certainly
/// meant something else. Cron and ISO timestamps are unaffected (cron
/// is per-minute by construction; ISO is single-fire).
const _noAgentMinInterval = Duration(seconds: 60);

ScheduleSpec _parseSpec(String raw) {
  // Try ISO-8601 timestamp first (most specific).
  final iso = DateTime.tryParse(raw);
  if (iso != null) {
    return OneShotSpec(iso.toUtc());
  }
  // Then duration like "30m", "1h", "1d".
  final dur = parseSchedule(raw);
  if (dur != null) {
    return IntervalSpec(dur);
  }
  // Then cron expression (5 fields).
  if (raw.split(RegExp(r"\s+")).length == 5) {
    return CronSpec(CronExpression.parse(raw));
  }
  throw FormatException(
    "Schedule must be a duration (`30m`), ISO timestamp "
    "(`2026-05-15T14:00Z`), or 5-field cron expression: $raw",
  );
}

final _telegramDeliver = RegExp(r"^telegram\(\s*([^)]+)\s*\)$");

DeliverTarget _parseDeliver(Object? raw) {
  if (raw == null) {
    return const DeliverOrigin();
  }
  if (raw is! String) {
    throw const FormatException("`deliver` must be a string");
  }
  final trimmed = raw.trim();
  if (trimmed == "origin") {
    return const DeliverOrigin();
  }
  if (trimmed == "none") {
    return const DeliverNone();
  }
  final m = _telegramDeliver.firstMatch(trimmed);
  if (m != null) {
    return DeliverTelegram(m.group(1)!.trim());
  }
  throw FormatException(
    "`deliver` must be `origin`, `none`, or `telegram(<chat_id>)`: $raw",
  );
}
