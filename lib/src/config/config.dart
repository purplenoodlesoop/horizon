import "package:freezed_annotation/freezed_annotation.dart";
import "package:pure/pure.dart";

part "config.freezed.dart";

mixin _ModeMixin {}

sealed class Mode<T extends Record> = TaggedRecord<T> with _ModeMixin;

final class HumanMode = Mode<()> with _ModeMixin;

final class AgentMode = Mode<()> with _ModeMixin;

@freezed
abstract class HorizonConfig with _$HorizonConfig {
  const factory HorizonConfig({
    required String telegramToken,
    required String telegramUsername,
    required String fireworksToken,
    required String tavilyToken,
    required String vaultPath,
    required Mode<()> mode,
    required String allowlistPath,
    required String templatesPath,
    required Duration heartbeatInterval,
  }) = _HorizonConfig;
}
