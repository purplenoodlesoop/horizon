import "dart:async";

import "package:horizon/src/event/event.dart";

const _defaultWindow = Duration(milliseconds: 1500);

/// Coalesces consecutive Telegram messages from the same chat into a
/// single event. When a Telegram event arrives, we wait [window] for
/// another from the same chat. If one arrives, the timer resets; if
/// not, the buffered events are emitted as one combined event with
/// `\n\n---\n\n` between parts.
///
/// CLI, schedule, and heartbeat events pass through untouched. Admin
/// commands (content starting with `/`) bypass batching too — folding
/// `/quiet` into adjacent text would break the harness's admin-command
/// intercept.
Stream<Event> batchTelegramEvents(
  Stream<Event> input, {
  Duration window = _defaultWindow,
}) {
  late StreamController<Event> out;
  final pending = <String, List<Event>>{};
  final timers = <String, Timer>{};
  StreamSubscription<Event>? sub;

  void flush(String chatId) {
    timers.remove(chatId);
    final list = pending.remove(chatId);
    if (list == null || list.isEmpty || out.isClosed) {
      return;
    }
    out.add(list.length == 1 ? list.single : _combine(list));
  }

  void flushAll() {
    pending.keys.toList().forEach(flush);
  }

  out = StreamController<Event>(
    onListen: () {
      sub = input.listen(
        (event) {
          final channel = event.channel;
          if (channel is! TelegramChannel) {
            out.add(event);
            return;
          }
          final content = event.content.trimLeft();
          if (content.startsWith("/")) {
            flush(channel.value.chatId);
            out.add(event);
            return;
          }
          final chatId = channel.value.chatId;
          (pending[chatId] ??= <Event>[]).add(event);
          timers[chatId]?.cancel();
          timers[chatId] = Timer(window, () => flush(chatId));
        },
        onError: out.addError,
        onDone: () {
          flushAll();
          unawaited(out.close());
        },
      );
    },
    onCancel: () {
      timers.values.forEach((t) => t.cancel());
      timers.clear();
      pending.clear();
      return sub?.cancel();
    },
  );

  return out.stream;
}

Event _combine(List<Event> events) {
  final last = events.last;
  final combined = events.map((e) => e.content).join("\n\n---\n\n");
  return Event(
    id: last.id,
    content: "[${events.length} messages received in burst]\n\n$combined",
    channel: last.channel,
    timestamp: last.timestamp,
    parentId: last.parentId,
  );
}
