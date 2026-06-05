import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/agent_event.dart";
import "package:horizon/src/agent/pipeline.dart";
import "package:horizon/src/agent/system_prompt.dart";
import "package:horizon/src/agent/working_state.dart";
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

/// #38: ground the model's self-knowledge in its REAL, current tools.
/// The system prompt otherwise advertises only capability descriptions
/// and bare tool schemas, so the model infers affordances and fabricates
/// ones it lacks (promising sends it can't do, asking for a chat_id that
/// cannot satisfy the outbound gate). Derived from the LIVE allowlist
/// every turn — dynamic real state, not a hand-written capability sheet.
String _renderAffordances(IList<AllowlistedTool> allowlist) {
  if (allowlist.isEmpty) {
    return "";
  }
  final names = allowlist.map((t) => t.name).join(", ");
  final hasTelegramSend = allowlist.any(
    (t) => t.parameters.values.any((p) => p.type == "telegram_chat_id"),
  );
  final buffer = StringBuffer()
    ..writeln()
    ..writeln()
    ..writeln(
      "[Your actual tools right now] These are the ONLY actions you can "
      "take: $names.",
    )
    ..writeln(
      "If something you are asked to do has no matching tool above, you "
      "cannot do it — say so plainly. Never claim or promise an action you "
      "have no tool for, and never report an action as done unless its "
      "tool returned success this turn.",
    );
  if (hasTelegramSend) {
    buffer.writeln(
      "Outbound messaging only reaches a chat that has already messaged "
      "this bot; an unknown chat_id is rejected. You cannot initiate "
      "contact with someone new, reach a person by @username, or look up a "
      "chat_id — do not ask the user for one as a workaround, it cannot "
      "work.",
    );
  }
  return buffer.toString();
}

/// Builds the user message: per-event volatile content goes here so
/// the system prompt above stays cacheable.
///
/// The working-memory notes (when present) are prepended as BACKGROUND —
/// not authority. They are the product of an explicit `/dream`
/// consolidation, so they can be stale; the live vault and what the user
/// says THIS turn are the source of truth. Framing them as "orient, then
/// verify" is deliberate (#36): the previous "current and authoritative,
/// never contradict" framing let stale/fabricated notes override reality
/// and re-asserted the model's own inventions as user-established fact.
String _buildUserMessage(
  String eventSummary,
  String eventContent,
  String workingState,
) {
  final wm = workingState.trim();
  final header = wm.isEmpty
      ? ""
      : "[Working notes — a background summary from your last /dream "
          "consolidation. Use it to orient, but it may be stale: the vault "
          "files and what the user says right now are the source of truth. "
          "If anything here conflicts with the user this turn, the user is "
          "right; verify against the vault before relying on a specific "
          "fact, and never present these notes as something the user "
          "established unless the vault confirms it.]\n$wm\n\n";
  return "$header$eventSummary\n\n[User content]\n$eventContent";
}

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
          final basePrompt = await LoadSystemPrompt(
            vaultPath: config.vaultPath,
            templatesPath: config.templatesPath,
            manifest: manifest,
            heartbeatMode: heartbeatMode,
          );
          // #38: ground the model in its real, current affordances.
          final systemPrompt = basePrompt + _renderAffordances(allowlist);
          final workingState = await LoadWorkingState(
            vaultPath: config.vaultPath,
          );
          final userMessage = _buildUserMessage(
            summary,
            event.content,
            workingState,
          );

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
                // For heartbeat events the implicit reply text is never
                // routed to a delivery channel (heartbeats have no chat_id
                // binding). Record hadReply=false so turn ledgers don't
                // claim the user received something they didn't.
                // Explicit `send_telegram` tool calls within a heartbeat
                // still deliver — they're tracked in toolsCalled separately.
                await WriteTurnRecord(
                  vaultPath: config.vaultPath,
                  event: event,
                  capabilitiesRead: result.capabilitiesRead,
                  toolsCalled: result.toolsCalled,
                  wrotePaths: result.writtenPaths,
                  hadReply: !heartbeatMode && replyText != null,
                );
                // #36: deliver the reply. There is no per-turn memory
                // rewrite anymore — durable facts live in the vault
                // (journal/knowledge/people, written by capabilities) and in
                // the conversation record; the working notes are refreshed
                // only by an explicit /dream. This removes the silent
                // generative digest that fabricated/dropped facts, plus its
                // second per-turn LLM round-trip.
                yield PipelineReply(event: event, text: replyText);
            }
          }
        });
}
