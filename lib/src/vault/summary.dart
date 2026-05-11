import "package:fast_immutable_collections/fast_immutable_collections.dart";

import "package:horizon/src/event/event.dart";

String formatChannelName(Channel<Object?> channel) => switch (channel) {
  TelegramChannel(:final value) => "telegram(${value.chatId})",
  CliChannel() => "cli",
  ScheduleChannel(:final value) => "schedule(${value.scheduleId})",
  InlineChannel(:final value) =>
      "telegram_inline(${value.inlineMessageId})",
};

String formatEventSummary(
  Event event,
  IList<Event> recentEvents,
  Duration decayThreshold,
) {
  final now = DateTime.now();
  final cutoff = now.subtract(decayThreshold);
  final relevant = recentEvents.where(
    (e) => e.timestamp.isAfter(cutoff) && e.id != event.id,
  );
  final buffer = StringBuffer()
    ..writeln("[Event Summary]")
    ..writeln("Time: ${event.timestamp.toIso8601String()}")
    ..writeln("Channel: ${formatChannelName(event.channel)}")
    ..writeln("Content: ${event.content}");
  if (event.parentId != null) {
    buffer.writeln("Parent event: ${event.parentId}");
  }
  if (relevant.isNotEmpty) {
    buffer.writeln("\n[Recent Events]");
    for (final e in relevant) {
      buffer.writeln(
        "- [${e.timestamp.toIso8601String()}] "
        "${formatChannelName(e.channel)}: ${e.content}",
      );
    }
  }
  return buffer.toString();
}
