import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/event/event.dart";
import "package:horizon/src/vault/summary.dart";

const _messagesSubdir = "_horizon/messages";

/// Whether an event represents a real channel-originated message
/// worth persisting. Heartbeat ticks are not.
bool isPersistableEvent(Event event) => !event.id.startsWith("heartbeat_");

String _safeTimestamp(DateTime ts) =>
    ts.toIso8601String().replaceAll(":", "-");

String _messagePath(String vaultPath, Event event) {
  final stamp = _safeTimestamp(event.timestamp);
  return "$vaultPath/$_messagesSubdir/$stamp-${event.id}.md";
}

String? _telegramChatId(Channel<Object?> channel) => switch (channel) {
  TelegramChannel(:final value) => value.chatId,
  CliChannel() => null,
  ScheduleChannel() => null,
};

String _renderInbound(Event event) {
  final chatId = _telegramChatId(event.channel);
  final buffer = StringBuffer()
    ..writeln("---")
    ..writeln("id: ${event.id}")
    ..writeln("channel: ${formatChannelName(event.channel)}")
    ..writeln("timestamp: ${event.timestamp.toIso8601String()}");
  if (chatId != null) {
    buffer.writeln("chat_id: $chatId");
  }
  if (event.parentId != null) {
    buffer.writeln("parent: ${event.parentId}");
  }
  buffer
    ..writeln("---")
    ..writeln()
    ..writeln("## In")
    ..writeln(event.content);
  return buffer.toString();
}

/// Writes the inbound side of a message file. Returns the path,
/// or null when the event is not persistable (e.g. heartbeat).
class WriteInboundMessage extends Fx<String?> {
  WriteInboundMessage({
    required String vaultPath,
    required Event event,
  }) : super(() {
        if (!isPersistableEvent(event)) {
          return null;
        }
        final path = _messagePath(vaultPath, event);
        final file = File(path);
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(_renderInbound(event));
        return path;
      });
}

/// Appends the system's reply(ies) to an existing message file.
/// Always writes a `## Out` section so the file structure is
/// invariant — empty replies are recorded as `(no reply)` rather
/// than silently omitted.
class AppendOutboundReply extends Fx<void> {
  AppendOutboundReply({
    required String? messagePath,
    required List<String> replies,
  }) : super(() {
        if (messagePath == null) {
          return;
        }
        final body = replies.isEmpty
            ? "(no reply)"
            : replies.join("\n\n");
        final buffer = StringBuffer()
          ..writeln()
          ..writeln("## Out")
          ..writeln(body);
        File(messagePath).writeAsStringSync(
          buffer.toString(),
          mode: FileMode.append,
        );
      });
}
