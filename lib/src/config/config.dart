import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:freezed_annotation/freezed_annotation.dart";
import "package:pure/pure.dart";

part "config.freezed.dart";

mixin _ModeMixin {}

sealed class Mode<T extends Record> = TaggedRecord<T> with _ModeMixin;

final class HumanMode = Mode<()> with _ModeMixin;

final class AgentMode = Mode<()> with _ModeMixin;

/// Static, startup-only configuration. Rotatable secrets and the
/// LLM endpoint config (`TELEGRAM_TOKEN`, `LLM_TOKEN`, `LLM_URL`,
/// `LLM_MODEL`, `TAVILY_TOKEN`, `TELEGRAM_USERNAME`) live in
/// `EnvStore`, not here, so they hot-reload on `.env` changes
/// without a process restart.
@freezed
abstract class HorizonConfig with _$HorizonConfig {
  const factory HorizonConfig({
    required String vaultPath,
    required Mode<()> mode,
    required String allowlistOverride,
    required IList<String> extraAllowlists,
    required String templatesPath,
    required Duration heartbeatInterval,
    required bool streamUi,
    required String envFilePath,
  }) = _HorizonConfig;
}
