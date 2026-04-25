import "dart:async";
import "dart:convert";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/pipelines/centralized.dart";
import "package:horizon/src/capability/capability.dart";
import "package:horizon/src/capability/lint.dart";
import "package:horizon/src/capability/schedule.dart";
import "package:horizon/src/channel/cli.dart";
import "package:horizon/src/channel/reply.dart";
import "package:horizon/src/channel/telegram.dart";
import "package:horizon/src/config/args.dart";
import "package:horizon/src/config/config.dart";
import "package:horizon/src/event/event.dart";
import "package:horizon/src/harness/bootstrap.dart";
import "package:horizon/src/harness/console_logger.dart";
import "package:horizon/src/harness/file_logger.dart";
import "package:horizon/src/harness/message_store.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:mark/mark.dart";
import "package:stream_transform/stream_transform.dart";

const _historyLimit = 100;

class RunHarness extends Fx<void> {
  RunHarness(List<String> args)
    : super(() async {
        final config = await ParseArgs(args);
        final timestamp = DateTime.now()
            .toIso8601String()
            .replaceAll(":", "-");
        final logPath = "logs/$timestamp.log";
        final fileProcessor = FileMessageProcessor.open(logPath);
        final isAgent = config.mode is AgentMode;
        final logger = Logger(
          processors: [
            if (!isAgent) const ConsoleMessageProcessor(),
            fileProcessor,
          ],
        );
        try {
          await _run(config, logger);
        } finally {
          await logger.dispose();
        }
      });
}

Future<void> _run(HorizonConfig config, Logger logger) async {
  await BootstrapVault(
    vaultPath: config.vaultPath,
    templatesPath: config.templatesPath,
    logger: logger,
  );

  // One-time startup audit. The richer semantic check is the
  // user-invokable lint-capabilities capability.
  final startupCaps = await LoadCapabilities(config.vaultPath);
  await WarnIdenticalDescriptions(
    capabilities: startupCaps,
    logger: logger,
  );

  logger.debug("Loading allowlist from ${config.allowlistPath}");

  final allowlist = await LoadAllowlist(config.allowlistPath);
  logger.debug("Loaded ${allowlist.length} tool(s)");

  final isAgent = config.mode is AgentMode;
  if (isAgent) {
    logger.debug("Running in agent mode");
  }

  final heartbeat = Stream<Event>.periodic(
    config.heartbeatInterval,
    (_) => heartbeatEvent(),
  );

  if (config.telegramUsername.isEmpty) {
    logger.warning(
      "TELEGRAM_USERNAME is not set — the bot will accept messages "
      "from any user and send to any chat_id. Set it in .env or "
      "via --telegram-username to lock the bot to a single user.",
    );
  }

  final events = TelegramPoller(
    botToken: config.telegramToken,
    allowedUsername: config.telegramUsername,
  ).merge(CliEvents()).merge(heartbeat);

  var history = IList<Event>();

  await for (final event in events) {
    if (isAgent) {
      _logJson({"type": "event", "id": event.id, "content": event.content});
    } else {
      logger.info("[${event.id}] ${event.content}");
    }
    history = _addToHistory(history, event);
    try {
      await _processEvent(
        event: event,
        allowlist: allowlist,
        config: config,
        history: history,
        logger: logger,
        isAgent: isAgent,
      );
    } on Exception catch (e, st) {
      logger.error("Pipeline error for ${event.id}: $e", stackTrace: st);
    }
  }
}

Future<void> _processEvent({
  required Event event,
  required IList<AllowlistedTool> allowlist,
  required HorizonConfig config,
  required IList<Event> history,
  required Logger logger,
  required bool isAgent,
}) async {
  // Re-read capabilities on every event so user edits in Obsidian
  // propagate immediately. Cheap directory listing.
  final capabilities = await LoadCapabilities(config.vaultPath);
  logger.debug("Loaded ${capabilities.length} capability(ies)");

  // Persist the inbound side of channel-originated events.
  final messagePath = await WriteInboundMessage(
    vaultPath: config.vaultPath,
    event: event,
  );

  // For heartbeat ticks, only proceed if at least one capability
  // declares itself due via its `schedule:` frontmatter. Otherwise
  // the harness skips the LLM entirely — heartbeats with nothing
  // due cost zero LLM calls.
  final isHeartbeat = event.id.startsWith("heartbeat_");
  IList<Capability> capsForPipeline;
  if (isHeartbeat) {
    final due = await DueCapabilities(
      capabilities: capabilities,
      vaultPath: config.vaultPath,
      now: DateTime.now(),
    );
    if (due.isEmpty) {
      logger.debug(
        "Heartbeat ${event.id}: no capabilities due — skipping LLM",
      );
      return;
    }
    logger.info(
      "Heartbeat ${event.id}: ${due.length} capability(ies) due — "
      "${due.map((c) => c.id).join(", ")}",
    );
    capsForPipeline = due;
  } else {
    capsForPipeline = capabilities;
  }

  // For Telegram channels, fire `sendChatAction(typing)` immediately
  // and re-arm every 4s while the pipeline runs — Telegram clears
  // the indicator after ~5s, so without re-arming the user would see
  // "typing..." vanish even while the orchestrator is still working.
  // The Fx in package:fn is a LazyFuture: it only runs when awaited,
  // so the periodic callback is async and awaits — `unawaited(SomeFx)`
  // would NOT trigger the http call.
  final stopwatch = Stopwatch()..start();
  Timer? typingTimer;
  if (event.channel is TelegramChannel && !isHeartbeat) {
    await SendChatActionTyping(
      channel: event.channel,
      telegramToken: config.telegramToken,
    );
    typingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await SendChatActionTyping(
        channel: event.channel,
        telegramToken: config.telegramToken,
      );
    });
  }

  final pipeline = RunCentralizedPipeline(
    event: event,
    capabilities: capsForPipeline,
    allowlist: allowlist,
    config: config,
    recentEvents: history,
    logger: logger,
    heartbeatMode: isHeartbeat,
  );
  final replies = <String>[];
  try {
    await for (final result in pipeline) {
      final text = result.agentText;
      if (text != null) {
        final timed = _withTiming(text, stopwatch.elapsed, event.channel);
        replies.add(timed);
        if (isAgent) {
          _logJson({"type": "agent_reply", "text": timed});
        } else {
          logger.info("[reply] $timed");
          await SendReply(
            channel: event.channel,
            text: timed,
            telegramToken: config.telegramToken,
          );
        }
      }
    }
  } finally {
    typingTimer?.cancel();
  }

  // Append the outbound side once the pipeline drains.
  await AppendOutboundReply(
    messagePath: messagePath,
    replies: replies,
  );

  if (!isAgent) {
    _logBlue("Processing complete for ${event.id}");
  }
}

IList<Event> _addToHistory(IList<Event> history, Event event) {
  final updated = history.add(event);
  if (updated.length > _historyLimit) {
    return updated.removeAt(0);
  }
  return updated;
}

void _logJson(Map<String, Object?> data) {
  stdout.writeln(jsonEncode(data));
}

void _logBlue(String message) {
  stdout.writeln("\x1B[34m$message\x1B[0m");
}

/// Appends "(took Xs)" / "(took Xm Ys)" to the reply, italicized
/// on Telegram via HTML, plain on CLI. Helps the user see how long
/// the orchestrator spent on this turn at a glance.
String _withTiming(
  String text,
  Duration elapsed,
  Channel<Object?> channel,
) {
  final secs = elapsed.inSeconds;
  final formatted = secs < 60
      ? "${secs}s"
      : "${secs ~/ 60}m ${secs % 60}s";
  return switch (channel) {
    TelegramChannel() => "$text\n\n<i>— $formatted</i>",
    CliChannel() => "$text\n\n— $formatted",
  };
}
