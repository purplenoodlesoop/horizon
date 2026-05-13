import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/agent_event.dart";
import "package:horizon/src/agent/pipeline.dart";
import "package:horizon/src/agent/system_prompt.dart";
import "package:horizon/src/capability/capability.dart";
import "package:horizon/src/config/config.dart";
import "package:horizon/src/config/env_store.dart";
import "package:horizon/src/event/event.dart";
import "package:horizon/src/harness/turn_store.dart";
import "package:horizon/src/llm/client.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/vault/summary.dart";
import "package:mark/mark.dart";

const _agentId = "horizon";
const heartbeatOkSentinel = "HEARTBEAT_OK";

String _renderManifest(IList<Capability> capabilities) {
  if (capabilities.isEmpty) {
    return "(no capabilities installed in <vault>/_horizon/capabilities/)";
  }
  return capabilities
      .map(
        (c) => "- ${c.id} (${c.relativePath}): ${c.description.trim()}",
      )
      .join("\n");
}

/// Builds the user message: per-event volatile content goes here so
/// the system prompt above stays cacheable.
String _buildUserMessage(String eventSummary, String eventContent) =>
    "$eventSummary\n\n[User content]\n$eventContent";

final _imageMarker = RegExp(r"\[image:([^\]\s]+)\]");

/// Extract vault-relative image paths from `[image:<relpath>]` markers
/// in the event content. The Telegram poller writes one of these per
/// inbound photo. Heartbeat / CLI / schedule events have no images.
final _scheduleTelegramDeliver = RegExp(r"^telegram\(\s*([^)]+)\s*\)$");

/// Resolve the "current Telegram chat" the orchestrator is implicitly
/// replying to. For `TelegramChannel` it's the inbound chat. For
/// `ScheduleChannel` it's the chat the schedule is configured to
/// deliver into (parsed from the `deliver:` tag) — same dedup rule:
/// the harness already routes the final reply to that chat, so the
/// LLM must not call `send_telegram` to it too.
String? _currentChatIdFor(Channel<Object?> channel) {
  switch (channel) {
    case TelegramChannel(:final value):
      return value.chatId;
    case ScheduleChannel(:final value):
      final m = _scheduleTelegramDeliver.firstMatch(value.deliver);
      return m?.group(1)?.trim();
    case CliChannel():
    case InlineChannel():
    case VaultChannel():
      return null;
  }
}

List<String> _extractImagePaths(String content, String vaultPath) =>
    _imageMarker
        .allMatches(content)
        .map((m) => "$vaultPath/${m.group(1)}")
        .toList(growable: false);

class RunCentralizedPipeline extends StreamFx<PipelineEvent> {
  RunCentralizedPipeline({
    required Event event,
    required IList<Capability> capabilities,
    required IList<AllowlistedTool> allowlist,
    required HorizonConfig config,
    required EnvStore envStore,
    required IList<Event> recentEvents,
    required Logger logger,
    bool heartbeatMode = false,
  }) : super(() async* {
          logger.debug(
            "Centralized pipeline, "
            "event=${event.id}, "
            "${capabilities.length} capability(ies)"
            "${heartbeatMode ? ' [heartbeat]' : ''}",
          );
          final summary = formatEventSummary(
            event,
            recentEvents,
            decayThreshold,
          );
          final manifest = _renderManifest(capabilities);
          final systemPrompt = await LoadSystemPrompt(
            vaultPath: config.vaultPath,
            templatesPath: config.templatesPath,
            manifest: manifest,
            heartbeatMode: heartbeatMode,
          );
          final userMessage = _buildUserMessage(summary, event.content);

          final currentChatId = _currentChatIdFor(event.channel);

          final imagePaths = _extractImagePaths(
            event.content,
            config.vaultPath,
          );

          final agent = RunAgentLlm(
            envStore: envStore,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            allowlist: allowlist,
            vaultPath: config.vaultPath,
            logger: logger,
            agentId: _agentId,
            currentTelegramChatId: currentChatId,
            imagePaths: imagePaths,
          );

          await for (final ae in agent) {
            switch (ae) {
              case AgentReasoningDelta(:final text):
                yield PipelineReasoningDelta(text);
              case AgentTextDelta(:final text):
                yield PipelineTextDelta(text);
              case AgentTextReset():
                yield const PipelineTextReset();
              case AgentToolStarted(:final name, :final args):
                yield PipelineToolStarted(name: name, args: args);
              case AgentToolFinished(:final name, :final ok):
                yield PipelineToolFinished(name: name, ok: ok);
              case AgentFinished(:final result):
                final suppressed = heartbeatMode &&
                    result.text?.trim() == heartbeatOkSentinel;
                final replyText = suppressed ? null : result.text;
                if (suppressed) {
                  logger.debug(
                    "[$_agentId] heartbeat OK — "
                    "suppressing sentinel reply",
                  );
                }
                await WriteTurnRecord(
                  vaultPath: config.vaultPath,
                  event: event,
                  capabilitiesRead: result.capabilitiesRead,
                  toolsCalled: result.toolsCalled,
                  wrotePaths: result.writtenPaths,
                  hadReply: replyText != null,
                );
                yield PipelineReply(event: event, text: replyText);
            }
          }
        });
}
