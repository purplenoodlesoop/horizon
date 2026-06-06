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
import "package:horizon/src/tool/security.dart";
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

/// A (#38 superseded): ground the model in its REAL tools AND its REAL
/// reachable set. The prompt otherwise advertises only descriptions and
/// bare schemas, so the model infers affordances and fabricates ones it
/// lacks — promising sends it cannot do, offering a chat_id workaround
/// the outbound gate will always reject. Derived from the LIVE allowlist
/// + the actual `_horizon/messages/` roster every turn: dynamic real
/// state, not a hand-written sheet and not generic "don't lie" prose.
String _renderAffordances(
  IList<AllowlistedTool> allowlist,
  String vaultPath,
  Set<String> allowedUsernames,
) {
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
    final reachable = loadAllowedChatIds(vaultPath);
    final reachableStr = reachable.isEmpty
        ? "(no one has messaged this bot yet)"
        : reachable.join(", ");
    final usernamesStr = allowedUsernames.isEmpty
        ? "(none configured)"
        : allowedUsernames.map((u) => "@$u").join(", ");
    buffer.writeln(
      "[Who you can actually reach] Reaching someone on Telegram needs BOTH "
      "of two things, and this chains in a way that has no workaround: (1) "
      "their username is in this bot's inbound allowlist — the ONLY allowed "
      "usernames are: $usernamesStr — and (2) they have already sent this "
      "bot a message, which is what records their chat_id. The chat_ids you "
      "can reach right now are: $reachableStr. Here is the chain that closes "
      "every loophole: a message from anyone NOT in the username allowlist "
      "is DROPPED the instant it arrives and never records a chat_id. So a "
      "person outside that allowlist can never become reachable by ANY "
      "route — you cannot message them, the user cannot hand you their "
      "chat_id (an unrecorded chat_id is rejected by the send gate), and "
      "'have them message the bot first' does NOT work either, because "
      "their message is dropped before it can count. For anyone not already "
      "in the reachable list, say plainly that you cannot reach them and "
      "that there is no workaround you can perform. The ONLY way to add "
      "someone is for the user to add that person's username to the bot's "
      "allowlist themselves — that is the user's own action on the bot's "
      "config, never something you can do, trigger, or promise.",
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
          // A: ground the model in its real affordances AND real reachable
          // roster (live allowlist + _horizon/messages/).
          final systemPrompt = basePrompt +
              _renderAffordances(
                allowlist,
                config.vaultPath,
                envStore.telegramUsernames,
              );
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
