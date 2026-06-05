import "dart:async";
import "dart:collection";
import "dart:convert";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/pipeline.dart";
import "package:horizon/src/agent/pipelines/centralized.dart";
import "package:horizon/src/capability/capability.dart";
import "package:horizon/src/capability/lint.dart";
import "package:horizon/src/capability/schedule.dart";
import "package:horizon/src/channel/cli.dart";
import "package:horizon/src/channel/reply.dart";
import "package:horizon/src/channel/telegram.dart";
import "package:horizon/src/channel/telegram_admin.dart";
import "package:horizon/src/channel/telegram_batch.dart";
import "package:horizon/src/channel/vault.dart";
import "package:horizon/src/config/args.dart";
import "package:horizon/src/config/config.dart";
import "package:horizon/src/config/env_store.dart";
import "package:horizon/src/config/env_watcher.dart";
import "package:horizon/src/config/preferences.dart";
import "package:horizon/src/event/event.dart";
import "package:horizon/src/harness/bootstrap.dart";
import "package:horizon/src/harness/console_logger.dart";
import "package:horizon/src/harness/file_logger.dart";
import "package:horizon/src/harness/message_store.dart";
import "package:horizon/src/harness/orphan_recovery.dart";
import "package:horizon/src/schedule/schedule.dart";
import "package:horizon/src/schedule/scheduler.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/tool/executor.dart";
import "package:mark/mark.dart";
import "package:stream_transform/stream_transform.dart";

const _historyLimit = 100;

class RunHarness extends Fx<void> {
  RunHarness(List<String> args)
      : super(() async {
          final parsed = await ParseArgs(args);
          final config = parsed.config;
          final envStore = parsed.envStore;
          final timestamp =
              DateTime.now().toIso8601String().replaceAll(":", "-");
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
            await _run(config, envStore, logger);
          } finally {
            await logger.dispose();
          }
        });
}

Future<void> _run(
  HorizonConfig config,
  EnvStore envStore,
  Logger logger,
) async {
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

  // Allowlist is resolved + reloaded per event so edits via Obsidian
  // Mobile take effect on the next user message — same hot-reload
  // discipline as capabilities. Startup just probes the resolved path
  // to fail fast on a missing file.
  final startupAllowlistPath = resolveAllowlistPath(
    vaultPath: config.vaultPath,
    templatesPath: config.templatesPath,
    override: config.allowlistOverride,
  );
  logger.debug("Allowlist source: $startupAllowlistPath");
  if (config.extraAllowlists.isNotEmpty) {
    logger.debug(
      "Extra allowlists: ${config.extraAllowlists.join(", ")}",
    );
  }
  final startupAllowlist = await LoadAllowlist(
    startupAllowlistPath,
    extraPaths: config.extraAllowlists,
  );
  logger.debug("Loaded ${startupAllowlist.length} tool(s) at startup");

  final isAgent = config.mode is AgentMode;
  if (isAgent) {
    logger.debug("Running in agent mode");
  }

  final heartbeat = Stream<Event>.periodic(
    config.heartbeatInterval,
    (_) => heartbeatEvent(),
  );

  if (envStore.telegramUsernames.isEmpty) {
    logger.warning(
      "TELEGRAM_USERNAME is not set — Telegram inbound is FAIL-CLOSED: "
      "all messages will be dropped, including yours. Set "
      "TELEGRAM_USERNAME in .env (without `@`, comma-separated for "
      "multiple users) or pass --telegram-username to allow accounts.",
    );
  } else {
    logger.info(
      "Telegram inbound allowlist: "
      "${envStore.telegramUsernames.map((u) => "@$u").join(", ")}",
    );
  }

  // Telegram poller restart-on-rotation: the poller is constructed
  // with the current TELEGRAM_TOKEN/USERNAME; if either changes (env
  // file edited, .env reload picks it up), we cancel the current
  // subscription and start a fresh poller. The downstream merge
  // sees a single continuous stream via the controller.
  final telegramOut = StreamController<Event>();
  StreamSubscription<Event>? telegramSub;
  void startPoller() {
    final old = telegramSub;
    if (old != null) {
      unawaited(old.cancel());
    }
    if (envStore.telegramToken.isEmpty) {
      logger.warning("Telegram poller idle: TELEGRAM_TOKEN is empty");
      telegramSub = null;
      return;
    }
    telegramSub = TelegramPoller(
      botToken: envStore.telegramToken,
      allowedUsernames: envStore.telegramUsernames,
      vaultPath: config.vaultPath,
      logger: logger,
    ).listen(
      telegramOut.add,
      onError: (Object e, StackTrace st) =>
          logger.error("Telegram poller error: $e", stackTrace: st),
    );
  }

  startPoller();

  // Live .env reload: file-watch in parallel with the event loop.
  // On token rotation, restart the poller transparently.
  // Fx is a LazyFuture: `unawaited(SomeFx)` would NOT trigger the
  // body. Always `.asFuture()` for fire-and-forget — see
  // `spec/lessons-from-live-use.md` §5.
  unawaited(WatchEnvFile(
    store: envStore,
    logger: logger,
    onReload: (diff) {
      if (diff.affectsTelegramConnection()) {
        logger.info(
          "Telegram credentials changed — reconnecting poller",
        );
        startPoller();
      }
    },
  ).asFuture());

  // Scheduler stream: emits one synthetic event per due schedule on
  // its own tick. Schedules with `no_agent: true` are short-circuited
  // here — they run a tool and deliver verbatim, never reaching the
  // orchestrator.
  final scheduler = Scheduler(vaultPath: config.vaultPath, logger: logger);
  final scheduleOut = StreamController<Event>();
  unawaited(_runScheduler(
    scheduler: scheduler,
    out: scheduleOut,
    envStore: envStore,
    config: config,
    logger: logger,
  ));

  // Vault-watcher: capabilities that declare `watch:` globs in their
  // frontmatter receive an event on each matching filesystem change.
  // Glob set is fixed at startup from startupCaps; adding new globs
  // requires a restart (capability bodies still hot-reload per event).
  final watchPatterns = startupCaps.expand((c) => c.watch).toSet();
  if (watchPatterns.isNotEmpty) {
    logger.info(
      "Vault watcher: ${watchPatterns.length} glob pattern(s) from "
      "${startupCaps.where((c) => c.watch.isNotEmpty).length} capability(ies)",
    );
  }

  final events = batchTelegramEvents(telegramOut.stream)
      .merge(CliEvents())
      .merge(heartbeat)
      .merge(scheduleOut.stream)
      .merge(VaultWatchEvents(
        vaultPath: config.vaultPath,
        capabilities: startupCaps,
      ));

  var history = IList<Event>();
  var lastToolCount = startupAllowlist.length;

  // Priority-aware event dispatch (issue #14): user-facing events
  // (TelegramChannel, InlineChannel, CliChannel, VaultChannel) are
  // drained before queued heartbeat / schedule events. This prevents a
  // long-running heartbeat from blocking a tg_* message for minutes.
  //
  // Note: this prioritises the NEXT event chosen, not the currently
  // in-flight one. An already-running heartbeat pipeline is not
  // interrupted — but once it finishes, any waiting tg_* events are
  // processed first before the next heartbeat is picked up.
  final urgentQueue = Queue<Event>();
  final backgroundQueue = Queue<Event>();
  var eventStreamDone = false;
  var wakeup = Completer<void>();

  events.listen(
    (e) {
      if (_isUrgent(e)) {
        urgentQueue.add(e);
      } else {
        backgroundQueue.add(e);
      }
      if (!wakeup.isCompleted) {
        wakeup.complete();
      }
    },
    onDone: () {
      eventStreamDone = true;
      if (!wakeup.isCompleted) {
        wakeup.complete();
      }
    },
    onError: (Object e, StackTrace st) {
      logger.error("Event stream error: $e", stackTrace: st);
    },
  );

  Event? pickNext() {
    if (urgentQueue.isNotEmpty) {
      return urgentQueue.removeFirst();
    }
    if (backgroundQueue.isNotEmpty) {
      return backgroundQueue.removeFirst();
    }
    return null;
  }

  Future<void> processEvent(Event event) async {
    if (isAgent) {
      _logJson({"type": "event", "id": event.id, "content": event.content});
    } else {
      logger.info("[${event.id}] ${event.content}");
    }
    // Pre-LLM admin command intercept on Telegram. Known commands
    // are handled structurally (no LLM); unknown `/`-prefixes fall
    // through to the orchestrator. CLI is unaffected (the user
    // already has shell access).
    if (event.channel is TelegramChannel) {
      final cmd = parseAdminCommand(event.content);
      if (cmd != null) {
        await _handleAdminCommand(
          event: event,
          command: cmd,
          config: config,
          envStore: envStore,
          logger: logger,
        );
        return;
      }
    }
    history = _addToHistory(history, event);
    try {
      // Reload the allowlist per event — vault edits propagate
      // without restart, same discipline as capabilities. Extras
      // come from --extra-allowlist flags; their contents are
      // re-read each event too, so a NixOS rebuild that bumps a
      // store-path fragment takes effect on the next message.
      final liveAllowlist = await LoadAllowlist(
        resolveAllowlistPath(
          vaultPath: config.vaultPath,
          templatesPath: config.templatesPath,
          override: config.allowlistOverride,
        ),
        extraPaths: config.extraAllowlists,
      );
      if (liveAllowlist.length != lastToolCount) {
        logger.info(
          "Allowlist reload: $lastToolCount → ${liveAllowlist.length} "
          "tool(s)",
        );
        lastToolCount = liveAllowlist.length;
      }
      final replies = await _processEvent(
        event: event,
        allowlist: liveAllowlist,
        config: config,
        envStore: envStore,
        history: history,
        logger: logger,
        isAgent: isAgent,
      );
      // Push orchestrator's own replies into history so the next
      // turn's LLM sees what it just said. Without this, the
      // orchestrator is amnesic about its own outputs — a user's
      // terse answer to a question the orchestrator just asked
      // ("spin a task", "yes", "do it") arrives without the
      // question in the LLM's working memory and gets bound to
      // whichever recent inbound message the LLM finds most
      // prominent. Observed 2026-05-20: wrong-topic dispatch.
      if (replies.isNotEmpty) {
        final joined = replies.join("\n\n");
        final truncated = joined.length > 1500
            ? "${joined.substring(0, 1499)}…"
            : joined;
        final selfEvent = Event(
          id: "self_${event.id}",
          content: "[your prior reply] $truncated",
          channel: event.channel,
          timestamp: DateTime.now(),
        );
        history = _addToHistory(history, selfEvent);
      }
    } on Exception catch (e, st) {
      logger.error("Pipeline error for ${event.id}: $e", stackTrace: st);
    }
  }

  try {
    while (!eventStreamDone ||
        urgentQueue.isNotEmpty ||
        backgroundQueue.isNotEmpty) {
      var event = pickNext();
      if (event == null) {
        await wakeup.future;
        wakeup = Completer<void>();
        event = pickNext();
        if (event == null) {
          continue;
        }
      }
      await processEvent(event);
    }
  } finally {
    await telegramSub?.cancel();
    await telegramOut.close();
    await scheduleOut.close();
  }
}

Future<List<String>> _processEvent({
  required Event event,
  required IList<AllowlistedTool> allowlist,
  required HorizonConfig config,
  required EnvStore envStore,
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

  // Issue #13: deterministic recovery for tg_* events that closed
  // with had_reply: false (LLM dropped the message, pipeline crashed,
  // etc.). Runs on every heartbeat before the due-capability check
  // so even idle heartbeats deliver the safety net. The scanner
  // self-dedupes via a sidecar marker and cross-checks the message
  // file's `## Out` section so the issue #11 fallback isn't doubled.
  if (isHeartbeat) {
    try {
      final recovered = await RecoverOrphanedTurns(
        vaultPath: config.vaultPath,
        telegramToken: envStore.telegramToken,
        lookback: const Duration(minutes: 15),
        now: DateTime.now(),
        logger: logger,
      );
      if (recovered > 0) {
        logger.info(
          "[orphan-recovery] $recovered tg_* turn(s) recovered",
        );
      }
    } on Exception catch (e, st) {
      logger.error("Orphan recovery failed: $e", stackTrace: st);
    }
  }

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
      return const [];
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
      telegramToken: envStore.telegramToken,
    );
    typingTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await SendChatActionTyping(
        channel: event.channel,
        telegramToken: envStore.telegramToken,
      );
    });
  }

  final pipeline = RunCentralizedPipeline(
    event: event,
    capabilities: capsForPipeline,
    allowlist: allowlist,
    config: config,
    envStore: envStore,
    recentEvents: history,
    logger: logger,
    heartbeatMode: isHeartbeat,
  );
  final replies = <String>[];
  TelegramLiveReply? live;
  if (event.channel is TelegramChannel && !isHeartbeat) {
    // Vault override of the CLI flag, so `/quiet` and `/loud` (or a
    // hand-edit of preferences.md) take effect on the next event with
    // no restart. Mode (agent/human) is orthogonal: Telegram still
    // gets live edits in agent mode; stdout JSON is purely additive.
    final prefs = await LoadPreferences(
      vaultPath: config.vaultPath,
      fallback: Preferences(streamUi: config.streamUi),
    );
    live = TelegramLiveReply(
      token: envStore.telegramToken,
      chatId: (event.channel as TelegramChannel).value.chatId,
      streaming: prefs.streamUi,
    );
    // In quiet mode this immediately sends "Thinking…" so the user
    // sees a reaction before any tool work begins. In streaming
    // mode it's a no-op — the first show* call sends the placeholder.
    await live.start();
  }
  // Mode/output orthogonality: `live` (Telegram edits) and `_logJson`
  // (agent stdout) and `stdout.write` (human CLI streaming) are
  // independent. Each pipeline event fires every channel that
  // applies. agent mode = "ALSO emit JSON to stdout"; never "skip
  // Telegram delivery".
  var streamingToStdout = false;
  var streamedAnyText = false;
  final ch = event.channel;
  final isCliHuman = ch is CliChannel && !isAgent;
  try {
    await for (final pe in pipeline) {
      switch (pe) {
        case PipelineReasoningDelta(:final text):
          if (live != null) {
            live.showReasoning(text);
          }
          if (isAgent) {
            _logJson({"type": "reasoning_delta", "text": text});
          }
        case PipelineTextDelta(:final text):
          if (live != null) {
            live.showAnswer(text);
          }
          if (isAgent) {
            _logJson({"type": "text_delta", "text": text});
          }
          if (isCliHuman) {
            stdout.write(text);
            streamingToStdout = true;
            streamedAnyText = true;
          }
        case PipelineTextReset():
          if (live != null) {
            live.resetAnswer();
          }
          if (isAgent) {
            _logJson({"type": "text_reset"});
          }
          if (isCliHuman && streamingToStdout) {
            stdout
              ..writeln()
              ..writeln("[discarded intermediate narration]");
            streamingToStdout = false;
            streamedAnyText = false;
          }
        case PipelineToolStarted(:final name, :final args):
          if (live != null) {
            live.showTool(name, args);
          }
          if (isAgent) {
            _logJson({
              "type": "tool_started",
              "name": name,
              "args": args.unlock,
            });
          }
          if (isCliHuman) {
            if (streamingToStdout) {
              stdout.writeln();
              streamingToStdout = false;
            }
            logger.debug("[tool] $name(${_briefArgs(args)})");
          }
        case PipelineToolFinished(:final name, :final ok):
          if (isAgent) {
            _logJson({"type": "tool_finished", "name": name, "ok": ok});
          }
        case PipelineReply(:final text):
          if (text != null) {
            final normalized = event.channel is TelegramChannel ||
                    event.channel is InlineChannel
                ? _normalizeMarkdownToHtml(text)
                : text;
            final timed = _withTiming(
              normalized,
              stopwatch.elapsed,
              event.channel,
            );
            replies.add(timed);
            if (isAgent) {
              _logJson({"type": "agent_reply", "text": timed});
            }
            // Side-effect delivery — runs regardless of mode.
            if (ch is ScheduleChannel) {
              await _routeScheduleReply(
                deliver: parseDeliverTag(ch.value.deliver),
                reply: timed,
                envStore: envStore,
                logger: logger,
              );
              logger.info("[reply] $timed");
            } else if (live != null) {
              await live.finalize(timed);
              logger.info("[reply] $timed");
            } else if (ch is TelegramChannel) {
              // Telegram with stream UI off (or heartbeat — though
              // heartbeats don't usually reply).
              await SendReply(
                channel: ch,
                text: timed,
                telegramToken: envStore.telegramToken,
              );
              logger.info("[reply] $timed");
            } else if (ch is InlineChannel) {
              // Inline mode: bot edits the placeholder article it
              // posted on chosen_inline_result with the final reply.
              // No live streaming (we'd need a separate edit-by-
              // inline_message_id path) — a single post-LLM edit is
              // enough. Prepend the original query as a blockquote
              // so the conversation isn't lost once the placeholder
              // is overwritten (the user typed it inline; without
              // this prefix only the answer would remain).
              final quoted = "<blockquote>"
                  "${_htmlEscape(event.content)}</blockquote>\n\n"
                  "$timed";
              await SendReply(
                channel: ch,
                text: quoted,
                telegramToken: envStore.telegramToken,
              );
              logger.info("[reply] $quoted");
            } else if (streamedAnyText) {
              // CLI human mode: tokens already in stdout, just
              // append the timing footer.
              if (streamingToStdout) {
                stdout.writeln();
                streamingToStdout = false;
              }
              final footer = _trailingFooter(
                timed.substring(text.length),
              );
              if (footer.isNotEmpty) {
                stdout.writeln(footer);
              }
              logger.debug("[reply] (${text.length} chars) $timed");
            } else {
              // No delivery channel (e.g. heartbeat with non-sentinel
              // implicit reply text). Log as discarded so turn ledgers
              // and journalctl don't claim the user received something
              // they didn't — the [reply] label implies delivery.
              logger.warning(
                "[reply-discarded] ${event.id}: "
                "${text.length} chars of implicit reply text have no "
                "delivery destination and were not sent to the user",
              );
            }
          }
      }
    }
  } finally {
    typingTimer?.cancel();
    if (streamingToStdout) {
      stdout.writeln();
    }
  }

  // Issue #11: if the LLM produced zero completion tokens the pipeline
  // yields PipelineReply(text: null) and `replies` stays empty, leaving
  // the "Thinking…" Telegram placeholder stuck indefinitely. Detect this
  // and finalize with a user-visible fallback so the chat is never silent.
  if (live != null && replies.isEmpty) {
    logger.warning(
      "[${event.id}] LLM returned completion=0 — "
      "finalizing live reply with fallback message",
    );
    const fallback = "I didn't catch that — please try again.";
    await live.finalize(fallback);
    replies.add(fallback);
  }

  // Append the outbound side once the pipeline drains.
  await AppendOutboundReply(
    messagePath: messagePath,
    replies: replies,
  );

  if (!isAgent) {
    _logBlue("Processing complete for ${event.id}");
  }
  return replies;
}

Future<void> _runScheduler({
  required Scheduler scheduler,
  required StreamController<Event> out,
  required EnvStore envStore,
  required HorizonConfig config,
  required Logger logger,
}) async {
  await for (final fire in scheduler.tick()) {
    scheduler.recordFire(fire.schedule, fire.firedAt);
    if (fire.schedule.noAgent) {
      // Watchdog mode: run the tool, deliver verbatim. Never the LLM.
      try {
        // Reload the allowlist at fire time so a freshly-edited tool
        // is available to watchdog jobs without restart.
        final allowlist = await LoadAllowlist(
          resolveAllowlistPath(
            vaultPath: config.vaultPath,
            templatesPath: config.templatesPath,
            override: config.allowlistOverride,
          ),
          extraPaths: config.extraAllowlists,
        );
        await _runNoAgentSchedule(
          fire: fire,
          allowlist: allowlist,
          envStore: envStore,
          config: config,
          logger: logger,
        );
      } on Exception catch (e, st) {
        logger.error(
          "no_agent schedule ${fire.schedule.id}: $e",
          stackTrace: st,
        );
      }
      continue;
    }
    out.add(scheduleEvent(fire));
  }
}

/// Parses `prompt` as `<tool> <arg1> <arg2>...` and dispatches the
/// tool through the same executor agent-invoked tools use. Empty
/// stdout is silent; non-empty is delivered to the schedule's
/// `deliver:` target.
Future<void> _runNoAgentSchedule({
  required ScheduleFire fire,
  required IList<AllowlistedTool> allowlist,
  required EnvStore envStore,
  required HorizonConfig config,
  required Logger logger,
}) async {
  final parts = fire.schedule.prompt.trim().split(RegExp(r"\s+"));
  if (parts.isEmpty || parts.first.isEmpty) {
    logger.warning(
      "no_agent schedule ${fire.schedule.id}: empty prompt",
    );
    return;
  }
  final toolName = parts.first;
  final tool = allowlist.where((t) => t.name == toolName).firstOrNull;
  if (tool == null) {
    logger.warning(
      "no_agent schedule ${fire.schedule.id}: unknown tool '$toolName'",
    );
    return;
  }
  // Map positional argv to the tool's parameter names in declared
  // order. Mismatched arity is reported and the schedule is skipped
  // until the user fixes it.
  final paramNames = tool.parameters.keys.toList();
  if (parts.length - 1 != paramNames.length) {
    logger.warning(
      "no_agent schedule ${fire.schedule.id}: tool '$toolName' "
      "expects ${paramNames.length} arg(s), got ${parts.length - 1}",
    );
    return;
  }
  final args = <String, String>{};
  for (var i = 0; i < paramNames.length; i++) {
    args[paramNames[i]] = parts[i + 1];
  }
  final result = await ExecuteTool(
    allowlist: allowlist,
    toolName: toolName,
    toolArgs: args.lock,
    vaultPath: config.vaultPath,
    envStore: envStore,
  );
  // Empty stdout (the harness's "(no output)" sentinel) → silent.
  // The executor returns "(no output)" exactly when stdout is
  // empty; intercept that to keep watchdog jobs quiet on success.
  final clean = result == "(no output)" ? "" : result.trim();
  if (clean.isEmpty) {
    logger.debug(
      "no_agent schedule ${fire.schedule.id}: silent",
    );
    return;
  }
  logger.info(
    "no_agent schedule ${fire.schedule.id}: ${clean.length} chars → "
    "${_deliverTagFor(fire.schedule.deliver)}",
  );
  // Telegram replies use parse_mode=HTML, so escape and wrap the raw
  // command output in <pre> so meta-chars don't 400 the API.
  final escaped = clean
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;");
  final reply = result.startsWith("Error")
      ? "<b>no_agent error</b> from <code>${fire.schedule.id}</code>"
          "\n<pre>$escaped</pre>"
      : "<pre>$escaped</pre>";
  await _routeScheduleReply(
    deliver: fire.schedule.deliver,
    reply: reply,
    envStore: envStore,
    logger: logger,
  );
}

String _deliverTagFor(DeliverTarget t) => switch (t) {
      DeliverNone() => "none",
      DeliverOrigin() => "origin",
      DeliverTelegram(:final chatId) => "telegram($chatId)",
    };

Future<void> _routeScheduleReply({
  required DeliverTarget deliver,
  required String reply,
  required EnvStore envStore,
  required Logger logger,
}) async {
  switch (deliver) {
    case DeliverNone():
      logger.debug("Schedule reply discarded (deliver: none)");
    case DeliverOrigin():
      // No origin recorded for this schedule; log and drop. Schedules
      // that need delivery should specify `telegram(<chat_id>)`
      // explicitly.
      logger.warning(
        "Schedule reply with deliver: origin has no origin recorded; "
        "drop. Use deliver: telegram(<chat_id>).",
      );
    case DeliverTelegram(:final chatId):
      await SendReply(
        channel: TelegramChannel((chatId: chatId)),
        text: reply,
        telegramToken: envStore.telegramToken,
      );
  }
}

Future<void> _handleAdminCommand({
  required Event event,
  required AdminCommand command,
  required HorizonConfig config,
  required EnvStore envStore,
  required Logger logger,
}) async {
  logger.info("[admin] ${event.id}: ${event.content}");
  try {
    // /dream does a full-corpus LLM consolidation that can take a while.
    // Send an immediate acknowledgement so the user isn't left waiting in
    // silence before the rebuilt-memory summary arrives.
    if (command is DreamCmd) {
      await SendReply(
        channel: event.channel,
        text: "💤 Dreaming… consolidating long-term memory into fresh "
            "working memory. This can take a moment.",
        telegramToken: envStore.telegramToken,
      );
    }
    final reply = await ExecuteAdminCommand(
      command: command,
      vaultPath: config.vaultPath,
      envStore: envStore,
      logger: logger,
    );
    await SendReply(
      channel: event.channel,
      text: reply,
      telegramToken: envStore.telegramToken,
    );
  } on Exception catch (e, st) {
    logger.error("Admin command error: $e", stackTrace: st);
    try {
      await SendReply(
        channel: event.channel,
        text: "Admin command failed: $e",
        telegramToken: envStore.telegramToken,
      );
    } on Object {
      // Best-effort error reply.
    }
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
/// Strips the leading whitespace/newlines that `_withTiming` inserts
/// before its "— Xs" footer so we can print just the footer when the
/// body has already been streamed to stdout.
String _trailingFooter(String suffix) => suffix.trim();

String _htmlEscape(String s) =>
    s.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;");

/// Best-effort Markdown → Telegram-HTML normalization. The standing
/// prompt instructs the model to emit Telegram HTML, but Kimi-class
/// models still slip into Markdown (`**bold**`, `__bold__`) habitually.
/// Telegram renders the raw asterisks as ugly noise, so we
/// post-process the most common offenders here. Only well-formed
/// pairs are converted; single asterisks and underscores are left
/// alone to avoid wrecking inline math, file paths, or code that
/// happens to contain those characters.
String _normalizeMarkdownToHtml(String s) => s
    // Markdown bold → <b>.
    .replaceAllMapped(
      RegExp(r"\*\*([^*\n][^*]*?[^*\n]|[^*\n])\*\*"),
      (m) => "<b>${m[1]}</b>",
    )
    .replaceAllMapped(
      RegExp(r"__([^_\n][^_]*?[^_\n]|[^_\n])__"),
      (m) => "<b>${m[1]}</b>",
    )
    // Markdown single-asterisk italic → <i>. Conservative: only
    // converts when delimiters are clearly bounding prose — start
    // / whitespace / opening bracket on the open side; end /
    // whitespace / closing bracket / sentence-end punct on the
    // close side; at least one Unicode letter inside, no asterisk
    // and no newline. Leaves `x*y`, `arr[*p]`, and `2 * x` alone.
    // Underscore italic (`_x_`) is NOT handled — false-positive
    // rate on identifiers like `foo_bar` is too high.
    .replaceAllMapped(
      RegExp(
        r'''(^|[\s(\[«„‹—–])\*([^*\n]*\p{L}[^*\n]*?)\*(?=[\s)\].,;:?!»"”›—–]|$)''',
        unicode: true,
      ),
      (m) => "${m[1]}<i>${m[2]}</i>",
    )
    // Telegram HTML has no <br>; the standing prompt warns about
    // this, but Kimi-class models keep emitting it anyway. Convert
    // to a real newline so the message renders cleanly instead of
    // falling back to plain text via the editMessageText 400 path.
    .replaceAll(RegExp(r"<br\s*/?>", caseSensitive: false), "\n");

String _briefArgs(IMap<String, String> args) {
  if (args.isEmpty) {
    return "";
  }
  final entries = args.entries.take(2).map((e) {
    final v = e.value.length > 40 ? "${e.value.substring(0, 39)}…" : e.value;
    return "${e.key}=$v";
  });
  return entries.join(", ");
}

/// Returns true for events that need low-latency processing (user-facing).
/// These are drained before queued heartbeat / schedule events in the
/// priority dispatcher (see issue #14).
bool _isUrgent(Event event) =>
    event.channel is TelegramChannel ||
    event.channel is InlineChannel ||
    event.channel is CliChannel ||
    event.channel is VaultChannel;

String _withTiming(
  String text,
  Duration elapsed,
  Channel<Object?> channel,
) {
  final secs = elapsed.inSeconds;
  final formatted = secs < 60 ? "${secs}s" : "${secs ~/ 60}m ${secs % 60}s";
  return switch (channel) {
    TelegramChannel() => "$text\n\n<i>— $formatted</i>",
    CliChannel() => "$text\n\n— $formatted",
    ScheduleChannel() => "$text\n\n— $formatted",
    InlineChannel() => "$text\n\n<i>— $formatted</i>",
    VaultChannel() => "$text\n\n— $formatted",
  };
}
