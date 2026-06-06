import "dart:async";
import "dart:convert";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/agent/agent_event.dart";
import "package:horizon/src/config/env_store.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/tool/executor.dart";
import "package:mark/mark.dart";
import "package:openai_dart/openai_dart.dart";

// Idle timeout: longest allowable gap between SSE chunks. Resets on
// every chunk. Lets long completions keep flowing as long as tokens
// keep arriving; only fails on truly stuck connections. Prior wall-
// clock 60s timeout fired on slow-but-progressing streams.
const _idleTimeout = Duration(seconds: 90);
// Retry the establishment phase (failure before any chunk arrives) with
// exponential backoff, so a transient provider blip — crof.ai 502s, rate
// limits, idle timeouts, connection drops — is ridden out instead of
// failing the whole turn. Mid-stream failures are not retried (partial
// output may already be visible); neither are permanent 4xx client
// errors. See _isRetryableLlmError. Backoff is 1,2,4,8s across attempts.
const _maxEstablishmentRetries = 4;

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
    required EnvStore envStore,
    required String systemPrompt,
    required String userMessage,
    required IList<AllowlistedTool> allowlist,
    required String vaultPath,
    required Logger logger,
    required String agentId,
    String? currentTelegramChatId,
    List<String> imagePaths = const [],
  }) : super(() async* {
          // Snapshot LLM endpoint config at request start. If any of
          // token/url/model rotates mid-turn the in-flight client
          // keeps using the old values; the next event's pipeline
          // picks up the new ones.
          final client = OpenAIClient.withApiKey(
            envStore.llmToken,
            baseUrl: envStore.llmUrl,
          );
          final model = envStore.llmModel;
          final tools = allowlist.map(_buildTool).toList();
          final messages = <ChatMessage>[
            ChatMessage.system(systemPrompt),
            _buildUserChatMessage(
              text: userMessage,
              imagePaths: imagePaths,
              logger: logger,
              agentId: agentId,
            ),
          ];
          try {
            yield* _runLoop(
              client: client,
              model: model,
              messages: messages,
              tools: tools,
              allowlist: allowlist,
              vaultPath: vaultPath,
              envStore: envStore,
              logger: logger,
              agentId: agentId,
              currentTelegramChatId: currentTelegramChatId,
            );
          } finally {
            client.close();
          }
        });
}

/// True if an establishment-phase LLM failure is worth retrying: a
/// transient provider/network problem (5xx incl. 502 Bad Gateway, 429
/// rate limit, request timeout, connection or stream hiccup) rather than
/// a permanent 4xx client error or an explicit abort.
bool _isRetryableLlmError(Object e) {
  if (e is TimeoutException || e is SocketException) {
    return true;
  }
  return switch (e) {
    RequestTimeoutException() => true,
    ConnectionException() => true,
    StreamException() => true,
    AbortedException() => false,
    ApiException(:final statusCode) => statusCode >= 500 || statusCode == 429,
    _ => true,
  };
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
    var firstChunkArrived = false;
    var lastReasoningLen = 0;
    var lastContentLen = 0;
    ChatStreamAccumulator? lastAcc;
    try {
      // Consume the SSE stream directly with `await for` so a stream error
      // (provider 5xx/502, connection drop, idle timeout) is caught by the
      // local try/catch and can be retried. The previous StreamController +
      // `yield* controller.stream` indirection forwarded such errors to the
      // downstream listener instead, escaping this retry entirely. The idle
      // `.timeout` resets on every event, so a long-but-progressing
      // completion keeps flowing; only a truly stalled gap fails.
      final stream = client.chat.completions
          .createStreamWithAccumulator(request)
          .timeout(
        _idleTimeout,
        onTimeout: (sink) => sink.addError(
          TimeoutException("LLM stream idle for ${_idleTimeout.inSeconds}s"),
        ),
      );
      await for (final acc in stream) {
        firstChunkArrived = true;
        lastAcc = acc;
        // Reasoning: prefer reasoning_content, fall back to reasoning.
        final r = acc.reasoningContent.isNotEmpty
            ? acc.reasoningContent
            : acc.reasoning;
        if (r.length > lastReasoningLen) {
          yield AgentReasoningDelta(r.substring(lastReasoningLen));
          lastReasoningLen = r.length;
        }
        final c = _sanitizeStreamingContent(acc.content);
        if (c.length > lastContentLen) {
          yield AgentTextDelta(c.substring(lastContentLen));
          lastContentLen = c.length;
        }
      }
      // Stream finished cleanly.
      if (lastAcc != null) {
        onComplete(lastAcc);
      }
      return;
    } on Object catch (e) {
      // Retry only an establishment-phase failure (before any chunk) that
      // is transient — provider 5xx/502, rate limit, timeout, connection or
      // stream hiccup — with exponential backoff. Mid-stream failures
      // (partial output already shown) and permanent 4xx client errors
      // propagate immediately.
      if (firstChunkArrived ||
          attempt >= _maxEstablishmentRetries ||
          !_isRetryableLlmError(e)) {
        rethrow;
      }
      final delay = e is RateLimitException && e.retryAfter != null
          ? e.retryAfter!
          : Duration(seconds: 1 << attempt);
      logger.warning(
        "[$agentId] LLM stream error before any chunk: $e — "
        "retry ${attempt + 1}/$_maxEstablishmentRetries "
        "in ${delay.inMilliseconds}ms",
      );
      await Future<void>.delayed(delay);
      continue;
    }
  }
}

Stream<AgentEvent> _runLoop({
  required OpenAIClient client,
  required String model,
  required List<ChatMessage> messages,
  required List<Tool> tools,
  required IList<AllowlistedTool> allowlist,
  required String vaultPath,
  required EnvStore envStore,
  required Logger logger,
  required String agentId,
  required String? currentTelegramChatId,
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
        model: model,
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
      final argErrors = <String?>[];
      for (final call in toolCalls) {
        // #31: tolerate malformed tool-call JSON. A FormatException here
        // used to propagate and kill the whole turn; instead record a
        // recoverable error the model reads on its next cycle.
        IMap<String, String> args;
        String? argError;
        try {
          args = _parseArgs(call.function.arguments);
        } on FormatException catch (e) {
          args = IMap<String, String>();
          argError = "Error: tool arguments were not valid JSON ($e). "
              "Re-issue the call with valid JSON arguments.";
          logger.warning(
            "[$agentId] bad tool-call JSON for ${call.function.name}: $e",
          );
        }
        parsedArgs.add(args);
        argErrors.add(argError);
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
          argErrors[i] != null
              ? Future<String>.value(argErrors[i]!)
              : _dispatchToolCall(
                  allowlist: allowlist,
                  toolName: toolCalls[i].function.name,
                  toolArgs: parsedArgs[i],
                  vaultPath: vaultPath,
                  envStore: envStore,
                  currentTelegramChatId: currentTelegramChatId,
                  logger: logger,
                  agentId: agentId,
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
    final raw = _stripThinkingTags(message.content?.trim() ?? "");
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

/// Strip `<think>…</think>` / `<thinking>…</thinking>` blocks the
/// model sometimes emits inside content. Some open-weight reasoning
/// models (Kimi K2.6 family) intermittently leak their thinking into
/// the content channel instead of `reasoning_content`; this catches
/// the structured tag form. Heuristic prose stripping is intentionally
/// not done here — the system prompt instructs the model not to
/// narrate, and false positives on real replies are worse than a
/// rare leak.
final _thinkingBlockRe = RegExp(
  r"<think(?:ing)?>[\s\S]*?</think(?:ing)?>",
  caseSensitive: false,
);

final _thinkingOpenRe = RegExp(
  r"<think(?:ing)?>",
  caseSensitive: false,
);

String _stripThinkingTags(String text) {
  if (text.isEmpty) {
    return text;
  }
  return text.replaceAll(_thinkingBlockRe, "").trim();
}

/// Sanitize accumulated streaming content: strip complete
/// `<think>…</think>` blocks and, if an opening `<think>` has no
/// matching close yet (the model is mid-thought), truncate the
/// returned content at that point so the user never sees a partial
/// thinking block in the live preview.
String _sanitizeStreamingContent(String accContent) {
  if (accContent.isEmpty) {
    return accContent;
  }
  final stripped = accContent.replaceAll(_thinkingBlockRe, "");
  final openMatch = _thinkingOpenRe.firstMatch(stripped);
  if (openMatch == null) {
    return stripped;
  }
  return stripped.substring(0, openMatch.start);
}

/// Construct the user message: plain text when no images are
/// attached (keeps the simpler string path for the common case), or a
/// multimodal `ContentPart` list when one or more `[image:…]` markers
/// landed in the event content. Missing/unreadable files are logged
/// and skipped — the model still gets the text marker, just not the
/// pixels.
ChatMessage _buildUserChatMessage({
  required String text,
  required List<String> imagePaths,
  required Logger logger,
  required String agentId,
}) {
  if (imagePaths.isEmpty) {
    return ChatMessage.user(text);
  }
  final parts = <ContentPart>[ContentPart.text(text)];
  for (final path in imagePaths) {
    final file = File(path);
    if (!file.existsSync()) {
      logger.warning(
        "[$agentId] image attachment missing on disk, skipping: $path",
      );
      continue;
    }
    try {
      final bytes = file.readAsBytesSync();
      final b64 = base64Encode(bytes);
      parts.add(ContentPart.imageBase64(
        mediaType: _mediaTypeFor(path),
        data: b64,
      ));
    } on Object catch (e) {
      logger.warning(
        "[$agentId] failed to read image $path: $e",
      );
    }
  }
  if (parts.length == 1) {
    return ChatMessage.user(text);
  }
  return ChatMessage.user(parts);
}

String _mediaTypeFor(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith(".png")) {
    return "image/png";
  }
  if (lower.endsWith(".gif")) {
    return "image/gif";
  }
  if (lower.endsWith(".webp")) {
    return "image/webp";
  }
  return "image/jpeg";
}

/// Wraps ExecuteTool with a same-conversation guard for `send_telegram`.
/// When the LLM is responding to a telegram event, it sees its final
/// content delivered to that chat automatically; if it ALSO calls
/// `send_telegram` targeting the same chat_id, the user sees a
/// duplicate. Refuse the call with an error message the model will
/// read on its next turn, instead of executing it.
Future<String> _dispatchToolCall({
  required IList<AllowlistedTool> allowlist,
  required String toolName,
  required IMap<String, String> toolArgs,
  required String vaultPath,
  required EnvStore envStore,
  required String? currentTelegramChatId,
  required Logger logger,
  required String agentId,
}) async {
  if (toolName == "send_telegram" &&
      currentTelegramChatId != null &&
      toolArgs["chat_id"] == currentTelegramChatId) {
    logger.warning(
      "[$agentId] Refused self-targeting send_telegram to chat "
      "$currentTelegramChatId — your reply is already delivered "
      "to this chat via the final assistant message.",
    );
    return "Error: refusing to send_telegram to the chat you are "
        "currently replying in (chat_id=$currentTelegramChatId). Your "
        "final assistant message is already delivered to this chat — "
        "calling send_telegram here produces a duplicate. Use "
        "send_telegram only for OTHER chats.";
  }
  // #31: a tool that throws at spawn (e.g. a ProcessException, or any
  // other execution failure) must not kill the whole turn — return the
  // failure as a tool result the model can read and react to next cycle.
  try {
    return await ExecuteTool(
      allowlist: allowlist,
      toolName: toolName,
      toolArgs: toolArgs,
      vaultPath: vaultPath,
      envStore: envStore,
      currentChatId: currentTelegramChatId,
    );
  } on Object catch (e) {
    logger.error("[$agentId] tool '$toolName' failed to execute: $e");
    return "Error: tool '$toolName' failed to execute: $e";
  }
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
