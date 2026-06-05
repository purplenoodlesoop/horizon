import "package:fast_immutable_collections/fast_immutable_collections.dart";

import "package:horizon/src/event/event.dart";

String formatChannelName(Channel<Object?> channel) => switch (channel) {
  TelegramChannel(:final value) => "telegram(${value.chatId})",
  CliChannel() => "cli",
  ScheduleChannel(:final value) => "schedule(${value.scheduleId})",
  InlineChannel(:final value) =>
      "telegram_inline(${value.inlineMessageId})",
  VaultChannel(:final value) =>
      "vault(${value.eventType}:${value.path})",
};

const _weekdays = [
  "Monday",
  "Tuesday",
  "Wednesday",
  "Thursday",
  "Friday",
  "Saturday",
  "Sunday",
];

/// #35: render a wall-clock time the model can actually trust — local
/// time with an explicit UTC offset and the weekday — instead of a
/// bare, zone-less ISO string it cannot reconcile with the (UTC) `now`
/// tool. This is the model's window onto the present moment, so it must
/// be unambiguous.
String localIsoWithOffset(DateTime dt) {
  final local = dt.isUtc ? dt.toLocal() : dt;
  final off = local.timeZoneOffset;
  final sign = off.isNegative ? "-" : "+";
  final hh = off.inHours.abs().toString().padLeft(2, "0");
  final mm = (off.inMinutes.abs() % 60).toString().padLeft(2, "0");
  final weekday = _weekdays[(local.weekday - 1) % 7];
  return "${local.toIso8601String()}$sign$hh:$mm ($weekday)";
}

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
    ..writeln("Time: ${localIsoWithOffset(event.timestamp)}")
    ..writeln("Channel: ${formatChannelName(event.channel)}")
    ..writeln("Content: ${event.content}");
  if (event.parentId != null) {
    buffer.writeln("Parent event: ${event.parentId}");
  }
  if (relevant.isNotEmpty) {
    buffer.writeln("\n[Recent Events]");
    for (final e in relevant) {
      buffer.writeln(
        "- [${localIsoWithOffset(e.timestamp)}] "
        "${formatChannelName(e.channel)}: ${e.content}",
      );
    }
  }
  return buffer.toString();
}
