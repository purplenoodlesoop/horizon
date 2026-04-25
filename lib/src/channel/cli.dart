import "dart:convert";
import "dart:io";

import "package:fn/fn.dart";

import "package:horizon/src/event/event.dart";

var _nextId = 0;

String _generateCliId() {
  _nextId++;
  return "cli_$_nextId";
}

class CliEvents extends StreamFx<Event> {
  CliEvents()
    : super(() => stdin
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .map(
            (line) => Event(
              id: _generateCliId(),
              content: line.trim(),
              channel: const CliChannel(()),
              timestamp: DateTime.now(),
            ),
          ));
}

Event heartbeatEvent() => Event(
  id: "heartbeat_${DateTime.now().millisecondsSinceEpoch}",
  content: "heartbeat",
  channel: const CliChannel(()),
  timestamp: DateTime.now(),
);
