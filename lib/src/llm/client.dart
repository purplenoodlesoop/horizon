import "dart:async";
import "dart:convert";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/agent_event.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/tool/executor.dart";
import "package:mark/mark.dart";
import "package:openai_dart/openai_dart.dart";

const _model = "accounts/fireworks/models/kimi-k2p5";
const _fireworksBaseUrl = "https://api.fireworks.ai/inference/v1";
// Idle timeout: longest allowable gap between SSE chunks. Resets on
// every chunk. Lets long completions keep flowing as long as tokens
// keep arriving; only fails on truly stuck connections. Prior wall-
// clock 60s timeout fired on slow-but-progressing streams.
const _idleTimeout = Duration(seconds: 90);
// Retry only the establishment phase: if the stream fails before any
// chunk arrives. Mid-stream failures are not retried because partial
// output may already be visible to the user.
const _maxEstablishmentRetries = 2;

const _capabilitiesPrefix = "_horizon/capabilities/";

// Map harness-internal param types to JSON Schema types so the
// LLM tool schema is valid. Custom types (path, telegram_chat_id)
// surface as plain strings to the model; their validation
// semantics are enforced harness-side in ExecuteTool.
const _customTypes = {"path", "telegram_chat_id"};

String _jsonSchemaType(String paramType) =>
    _customTypes.contains(paramType) ? "string" : paramType;

Tool _buildTool(AllowlistedTool tool) => Tool.function(
  name: tool.name,
  description: tool.description,
  parameters: {
    "type": "object",
    "properties": {
      for (final entry in tool.parameters.entries)
        entry.key: {
          "type": _jsonSchemaType(entry.value.type),
          "description": entry.value.description,
        },
    },
    "required": tool.parameters.keys.toList(),
  },
);

class RunAgentLlm extends StreamFx<AgentEvent> {
  RunAgentLlm({
    required String fireworksToken,
    required String systemPrompt,
    required String userMessage,
    required IList<AllowlistedTool> allowlist,
    required String vaultPath,
    required String telegramToken,
    required String tavilyToken,
    required Logger logger,
    required String agentId,
  }) : super(() async* {
          final client = OpenAIClient.withApiKey(
            fireworksToken,
            baseUrl: _fireworksBaseUrl,
          );
          final tools = allowlist.map(_buildTool).toList();
          final messages = <ChatMessage>[
            ChatMessage.system(systemPrompt),
            ChatMessage.user(userMessage),
          ];
          try {
            yield* _runLoop(
              client: client,
              messages: messages,
              tools: tools,
              allowlist: allowlist,
              vaultPath: vaultPath,
              telegramToken: telegramToken,
              tavilyToken: tavilyToken,
              logger: logger,
              agentId: agentId,
            );
          } finally {
            client.close();
          }
        });
}

/// Streams a single LLM call and emits per-cycle deltas. Returns
/// the final accumulator (with content, reasoning, tool calls,
/// finish reason, usage) when the SSE stream ends.
///
/// Idle timeout: cancels and retries (up to [_maxEstablishmentRetries]
/// total attempts) only if the failure happens before the first
/// chunk arrives. Once any chunk has been emitted, errors propagate.
Stream<AgentEvent> _streamCycle({
  required OpenAIClient client,
  required ChatCompletionCreateRequest request,
  required Logger logger,
  required String agentId,
  required void Function(ChatStreamAccumulator) onComplete,
}) async* {
  for (var attempt = 0; attempt <= _maxEstablishmentRetries; attempt++) {
    final controller = StreamController<AgentEvent>();
    Timer? idleTimer;
    var firstChunkArrived = false;
    StreamSubscription<ChatStreamAccumulator>? sub;
    ChatStreamAccumulator? lastAcc;
    var lastReasoningLen = 0;
    var lastContentLen = 0;

    void teardown() {
      idleTimer?.cancel();
      idleTimer = null;
      final s = sub;
      if (s != null) {
        unawaited(s.cancel());
      }
    }

    void failAndClose(Object error, [StackTrace? st]) {
      controller.addError(error, st);
      unawaited(controller.close());
    }

    void resetIdle() {
      idleTimer?.cancel();
      idleTimer = Timer(_idleTimeout, () {
        if (controller.isClosed) {
          return;
        }
        teardown();
        failAndClose(
          TimeoutException(
            "LLM stream idle for ${_idleTimeout.inSeconds}s",
          ),
        );
      });
    }

    resetIdle();
    sub = client.chat.completions
        .createStreamWithAccumulator(request)
        .listen(
      (acc) {
        firstChunkArrived = true;
        resetIdle();
        lastAcc = acc;
        // Reasoning: prefer reasoning_content, fall back to reasoning.
        final r = acc.reasoningContent.isNotEmpty
            ? acc.reasoningContent
            : acc.reasoning;
        if (r.length > lastReasoningLen) {
          final delta = r.substring(lastReasoningLen);
          lastReasoningLen = r.length;
          if (!controller.isClosed) {
            controller.add(AgentReasoningDelta(delta));
          }
        }
        final c = acc.content;
        if (c.length > lastContentLen) {
          final delta = c.substring(lastContentLen);
          lastContentLen = c.length;
          if (!controller.isClosed) {
            controller.add(AgentTextDelta(delta));
          }
        }
      },
      onDone: () {
        teardown();
        if (controller.isClosed) {
          return;
        }
        final acc = lastAcc;
        if (acc != null) {
          onComplete(acc);
        }
        unawaited(controller.close());
      },
      onError: (Object e, StackTrace st) {
        teardown();
        if (controller.isClosed) {
          return;
        }
        failAndClose(e, st);
      },
    );

    try {
      yield* controller.stream;
      // Successful completion of the inner stream — break out.
      return;
    } on Object catch (e) {
      // Establishment-phase failure: retry. Otherwise propagate.
      if (firstChunkArrived || attempt >= _maxEstablishmentRetries) {
        rethrow;
      }
      logger.warning(
        "[$agentId] LLM stream error before any chunk: $e — "
        "retry ${attempt + 1}/$_maxEstablishmentRetries",
      );
      continue;
    } finally {
      // Defensive: cancel even on consumer-cancellation paths where
      // `controller.stream` ends without our onDone/onError firing.
      await sub.cancel();
      idleTimer?.cancel();
    }
  }
}

Stream<AgentEvent> _runLoop({
  required OpenAIClient client,
  required List<ChatMessage> messages,
  required List<Tool> tools,
  required IList<AllowlistedTool> allowlist,
  required String vaultPath,
  required String telegramToken,
  required String tavilyToken,
  required Logger logger,
  required String agentId,
}) async* {
  var current = messages;
  final writtenPaths = <String>[];
  final toolsCalled = <String>[];
  final capabilitiesRead = <String>[];
  var totalPrompt = 0;
  var totalCached = 0;
  var totalCompletion = 0;
  var requestCount = 0;
  var nudgedForReply = false;

  while (true) {
    logger.debug(
      "[$agentId] LLM stream "
      "(${current.length} messages)",
    );

    ChatStreamAccumulator? accumulator;
    yield* _streamCycle(
      client: client,
      request: ChatCompletionCreateRequest(
        model: _model,
        messages: current,
        tools: tools,
      ),
      logger: logger,
      agentId: agentId,
      onComplete: (acc) => accumulator = acc,
    );

    requestCount++;

    if (accumulator == null) {
      logger.warning("[$agentId] Stream ended with no accumulator");
      yield AgentFinished((
        text: null,
        writtenPaths: writtenPaths.toIList(),
        toolsCalled: toolsCalled.toIList(),
        capabilitiesRead: capabilitiesRead.toIList(),
      ));
      return;
    }

    final acc = accumulator!;
    final usage = acc.usage;
    if (usage != null) {
      final prompt = usage.promptTokens;
      final cached = usage.promptTokensDetails?.cachedTokens ?? 0;
      final completion = usage.completionTokens ?? 0;
      totalPrompt += prompt;
      totalCached += cached;
      totalCompletion += completion;
      final pct = prompt == 0 ? 0 : (cached * 100 ~/ prompt);
      logger.debug(
        "[$agentId] usage: prompt=$prompt cached=$cached "
        "($pct%) completion=$completion",
      );
    }

    final completion = acc.toChatCompletion();
    final choice = completion.choices.firstOrNull;
    if (choice == null) {
      logger.warning("[$agentId] Empty response from LLM");
      yield AgentFinished((
        text: null,
        writtenPaths: writtenPaths.toIList(),
        toolsCalled: toolsCalled.toIList(),
        capabilitiesRead: capabilitiesRead.toIList(),
      ));
      return;
    }

    final message = choice.message;
    final toolCalls = message.toolCalls;

    // Cycle ends in tool calls — any content streamed during this
    // cycle was intermediate narration, not the final answer.
    if (toolCalls != null && toolCalls.isNotEmpty) {
      if (acc.content.isNotEmpty) {
        yield const AgentTextReset();
      }

      current = [
        ...current,
        ChatMessage.assistant(
          content: message.content,
          toolCalls: toolCalls,
        ),
      ];

      // Emit start events synchronously, run executions in parallel,
      // then emit finish events in original order.
      final parsedArgs = <IMap<String, String>>[];
      for (final call in toolCalls) {
        final args = _parseArgs(call.function.arguments);
        parsedArgs.add(args);
        logger.debug(
          "[$agentId] Tool: ${call.function.name}"
          "(${call.function.arguments})",
        );
        toolsCalled.add(call.function.name);
        if (call.function.name == "write_file") {
          final path = args["path"];
          if (path != null && !writtenPaths.contains(path)) {
            writtenPaths.add(path);
          }
        }
        if (call.function.name == "read_file") {
          final path = args["path"];
          if (path != null && path.startsWith(_capabilitiesPrefix)) {
            if (!capabilitiesRead.contains(path)) {
              capabilitiesRead.add(path);
            }
          }
        }
        yield AgentToolStarted(name: call.function.name, args: args);
      }

      final toolResults = await Future.wait([
        for (var i = 0; i < toolCalls.length; i++)
          ExecuteTool(
            allowlist: allowlist,
            toolName: toolCalls[i].function.name,
            toolArgs: parsedArgs[i],
            vaultPath: vaultPath,
            telegramToken: telegramToken,
            tavilyToken: tavilyToken,
          ),
      ]);

      for (var i = 0; i < toolCalls.length; i++) {
        final call = toolCalls[i];
        final result = toolResults[i];
        final ok = !result.startsWith("Error");
        logger.debug(
          "[$agentId] Tool result [${call.function.name}]: "
          "${result.length > 200 ? '${result.substring(0, 200)}...' : result}",
        );
        yield AgentToolFinished(name: call.function.name, ok: ok);
        current = [
          ...current,
          ChatMessage.tool(toolCallId: call.id, content: result),
        ];
      }
      continue;
    }

    // No tool calls — final cycle.
    final raw = message.content?.trim() ?? "";
    final reasoningC = message.reasoningContent?.trim() ?? "";
    final reasoningR = message.reasoning?.trim() ?? "";
    final reasoningRaw = reasoningC.isNotEmpty ? reasoningC : reasoningR;
    final effective = raw.isNotEmpty ? raw : reasoningRaw;
    if (raw.isEmpty && reasoningRaw.isNotEmpty) {
      logger.warning(
        "[$agentId] content empty, falling back to reasoning "
        "(${reasoningRaw.length} chars)",
      );
    }
    final refusal = message.refusal?.trim();
    final fromRefusal = refusal != null && refusal.isNotEmpty
        ? "(model refused) $refusal"
        : null;
    final text = effective.isEmpty || effective.startsWith("(Empty response:")
        ? fromRefusal
        : effective;

    // Kimi K2.5 occasionally finishes with no reply text after doing
    // real work — nudges once. See history of this comment for
    // rationale.
    if (text == null && toolsCalled.isNotEmpty && !nudgedForReply) {
      logger.warning(
        "[$agentId] Silent finish with ${toolsCalled.length} "
        "tool call(s) — nudging once for a reply",
      );
      nudgedForReply = true;
      // Streamed nothing this cycle was useful; drop it.
      yield const AgentTextReset();
      current = [
        ...current,
        ChatMessage.assistant(content: message.content ?? ""),
        ChatMessage.user(
          "You finished the work but did not send a reply to the "
          "user. Send a brief confirmation or answer now using "
          "what you found. Do not call any more tools.",
        ),
      ];
      continue;
    }

    _logTotals(
      logger: logger,
      agentId: agentId,
      requestCount: requestCount,
      totalPrompt: totalPrompt,
      totalCached: totalCached,
      totalCompletion: totalCompletion,
    );

    if (text == null && writtenPaths.isEmpty) {
      logger.debug("[$agentId] No output");
      yield AgentFinished((
        text: null,
        writtenPaths: const IList<String>.empty(),
        toolsCalled: toolsCalled.toIList(),
        capabilitiesRead: capabilitiesRead.toIList(),
      ));
      return;
    }
    logger.debug(
      "[$agentId] Done — ${writtenPaths.length} write(s), "
      "reply: ${text != null}",
    );
    yield AgentFinished((
      text: text,
      writtenPaths: writtenPaths.toIList(),
      toolsCalled: toolsCalled.toIList(),
      capabilitiesRead: capabilitiesRead.toIList(),
    ));
    return;
  }
}

void _logTotals({
  required Logger logger,
  required String agentId,
  required int requestCount,
  required int totalPrompt,
  required int totalCached,
  required int totalCompletion,
}) {
  if (totalPrompt == 0) {
    return;
  }
  final pct = totalCached * 100 ~/ totalPrompt;
  logger.info(
    "[$agentId] turn totals: requests=$requestCount "
    "prompt=$totalPrompt cached=$totalCached ($pct%) "
    "completion=$totalCompletion",
  );
}

IMap<String, String> _parseArgs(String argumentsJson) {
  final decoded = jsonDecode(argumentsJson);
  if (decoded is! Map) {
    return IMap();
  }
  final result = <String, String>{};
  for (final entry in decoded.entries) {
    final key = entry.key;
    final val = entry.value;
    if (key is String) {
      result[key] = val?.toString() ?? "";
    }
  }
  return result.toIMap();
}
