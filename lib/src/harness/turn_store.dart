import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/event/event.dart";

const _turnsSubdir = "_horizon/turns";

String _safeTimestamp(DateTime ts) =>
    ts.toIso8601String().replaceAll(":", "-");

String _renderList(IList<String> items) {
  if (items.isEmpty) {
    return "[]";
  }
  final buffer = StringBuffer();
  for (final item in items) {
    buffer.writeln("  - ${_yamlScalar(item)}");
  }
  return "\n${buffer.toString().trimRight()}";
}

String _yamlScalar(String s) {
  // Quote if contains characters that need it; otherwise plain.
  if (s.contains(":") || s.contains("#") || s.startsWith("-")) {
    final escaped = s.replaceAll('"', r'\"');
    return '"$escaped"';
  }
  return s;
}

/// Writes a structured per-turn record to `<vault>/_horizon/turns/`.
///
/// The record captures: which capabilities the orchestrator read,
/// which tools it called, what files it wrote. Used by the
/// `metacognitive-monitor` capability to detect capability-miss
/// patterns. The harness performs no analysis itself.
class WriteTurnRecord extends Fx<void> {
  WriteTurnRecord({
    required String vaultPath,
    required Event event,
    required IList<String> capabilitiesRead,
    required IList<String> toolsCalled,
    required IList<String> wrotePaths,
    required bool hadReply,
  }) : super(() {
        final stamp = _safeTimestamp(event.timestamp);
        final path = "$vaultPath/$_turnsSubdir/$stamp-${event.id}.md";
        final file = File(path);
        file.parent.createSync(recursive: true);
        final body =
            "---\n"
            "event_id: ${event.id}\n"
            "timestamp: ${event.timestamp.toIso8601String()}\n"
            "had_reply: $hadReply\n"
            "capabilities_read:${_renderList(capabilitiesRead)}\n"
            "tools_called:${_renderList(toolsCalled)}\n"
            "wrote_paths:${_renderList(wrotePaths)}\n"
            "---\n"
            "\n"
            "Turn record for event ${event.id}.\n";
        file.writeAsStringSync(body);
      });
}
