import "package:freezed_annotation/freezed_annotation.dart";
import "package:pure/pure.dart";

part "event.freezed.dart";

mixin _ChannelMixin {}

sealed class Channel<T extends Record> = TaggedRecord<T> with _ChannelMixin;

final class TelegramChannel = Channel<({String chatId})> with _ChannelMixin;

final class CliChannel = Channel<()> with _ChannelMixin;

/// A scheduler-fired event. Carries the originating schedule's id and
/// a deliver-tag string (`origin`, `telegram(<chat_id>)`, `none`) the
/// harness uses to route the reply.
final class ScheduleChannel
    = Channel<({String scheduleId, String deliver})> with _ChannelMixin;

/// A Telegram inline-mode event: the user invoked `@horizon <query>`
/// in some chat (any chat — the bot doesn't need to be a member) and
/// tapped the placeholder article we returned. Telegram gives us an
/// `inline_message_id` (not a chat_id + message_id pair) which is the
/// only handle we have for editing the message later. Replies go out
/// via `editMessageText` with that handle.
final class InlineChannel
    = Channel<({String inlineMessageId})> with _ChannelMixin;

/// A filesystem change inside the vault matched at least one
/// capability's `watch:` glob. Capability prose decides how to react
/// (read the file, post to a chat, etc.). The event has no reply
/// destination of its own — replies, if any, are sent via tools like
/// `send_telegram` to a chat_id the capability looks up from the
/// vault (e.g. `meta.yaml#telegram.chat_id` for Pot tasks).
final class VaultChannel
    = Channel<({String path, String eventType})> with _ChannelMixin;

@freezed
abstract class Event with _$Event {
  const factory Event({
    required String id,
    required String content,
    required Channel<Object?> channel,
    required DateTime timestamp,
    String? parentId,
  }) = _Event;
}
