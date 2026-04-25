import "package:freezed_annotation/freezed_annotation.dart";
import "package:pure/pure.dart";

part "event.freezed.dart";

mixin _ChannelMixin {}

sealed class Channel<T extends Record> = TaggedRecord<T> with _ChannelMixin;

final class TelegramChannel = Channel<({String chatId})> with _ChannelMixin;

final class CliChannel = Channel<()> with _ChannelMixin;

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
