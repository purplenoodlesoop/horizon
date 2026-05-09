import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/agent_event.dart";
import "package:horizon/src/agent/pipeline.dart";
import "package:horizon/src/agent/system_prompt.dart";
import "package:horizon/src/capability/capability.dart";
import "package:horizon/src/config/config.dart";
import "package:horizon/src/config/env_store.dart";
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

          final agent = RunAgentLlm(
            envStore: envStore,
            systemPrompt: systemPrompt,
            userMessage: userMessage,
            allowlist: allowlist,
            vaultPath: config.vaultPath,
            logger: logger,
            agentId: _agentId,
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
