import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/capability/capability.dart";

const _turnsSubdir = "_horizon/turns";
final _scheduleRegex = RegExp(r"^\s*(\d+)\s*([smhdw])\s*$");
final _capabilitiesReadEntry = RegExp(r"^\s*-\s+(.+)$");

/// Parses a duration string like "30m", "1h", "1d", "7d", "1w".
/// Returns null on unparseable input.
Duration? parseSchedule(String raw) {
  final match = _scheduleRegex.firstMatch(raw);
  if (match == null) {
    return null;
  }
  final n = int.parse(match.group(1)!);
  final unit = match.group(2)!;
  return switch (unit) {
    "s" => Duration(seconds: n),
    "m" => Duration(minutes: n),
    "h" => Duration(hours: n),
    "d" => Duration(days: n),
    "w" => Duration(days: n * 7),
    _ => null,
  };
}

/// Returns the timestamp of the most recent turn record that loaded
/// the capability with the given id, or null if no such turn exists.
/// Reads `_horizon/turns/*.md` and parses YAML frontmatter for
/// `capabilities_read` and `timestamp`.
DateTime? findLastFireTime({
  required String vaultPath,
  required String capabilityId,
}) {
  final dir = Directory("$vaultPath/$_turnsSubdir");
  if (!dir.existsSync()) {
    return null;
  }
  final marker = "_horizon/capabilities/$capabilityId.md";
  DateTime? latest;
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith(".md")) {
      continue;
    }
    final ts = _parseTurnTimestamp(entity, marker);
    if (ts != null && (latest == null || ts.isAfter(latest))) {
      latest = ts;
    }
  }
  return latest;
}

DateTime? _parseTurnTimestamp(File file, String capabilityMarker) {
  final lines = file.readAsLinesSync();
  if (lines.isEmpty || lines.first.trim() != "---") {
    return null;
  }
  String? timestampLine;
  var inCapabilitiesRead = false;
  var seenMarker = false;
  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim() == "---") {
      break;
    }
    if (line.startsWith("timestamp:")) {
      timestampLine = line.substring("timestamp:".length).trim();
      inCapabilitiesRead = false;
      continue;
    }
    if (line.startsWith("capabilities_read:")) {
      inCapabilitiesRead = true;
      continue;
    }
    if (inCapabilitiesRead) {
      if (line.isNotEmpty && !line.startsWith(" ") && !line.startsWith("-")) {
        inCapabilitiesRead = false;
        continue;
      }
      final entry = _capabilitiesReadEntry.firstMatch(line);
      if (entry != null && entry.group(1)!.trim() == capabilityMarker) {
        seenMarker = true;
      }
    }
  }
  if (!seenMarker || timestampLine == null) {
    return null;
  }
  return DateTime.tryParse(timestampLine);
}

/// Filters the given capabilities to those that are due to fire now,
/// based on each capability's `schedule` field and the timestamp of
/// its last firing recorded in `_horizon/turns/`. Capabilities with
/// no `schedule` field are never returned.
class DueCapabilities extends Fx<IList<Capability>> {
  DueCapabilities({
    required IList<Capability> capabilities,
    required String vaultPath,
    required DateTime now,
  }) : super(() {
        final due = <Capability>[];
        for (final cap in capabilities) {
          final scheduleStr = cap.schedule;
          if (scheduleStr == null) {
            continue;
          }
          final interval = parseSchedule(scheduleStr);
          if (interval == null) {
            continue;
          }
          final lastFire = findLastFireTime(
            vaultPath: vaultPath,
            capabilityId: cap.id,
          );
          if (lastFire == null || now.difference(lastFire) >= interval) {
            due.add(cap);
          }
        }
        return due.toIList();
      });
}
