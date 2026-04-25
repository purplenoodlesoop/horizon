import "dart:async";
import "dart:convert";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/tool/executor.dart";
import "package:mark/mark.dart";
import "package:openai_dart/openai_dart.dart";

const _model = "accounts/fireworks/models/kimi-k2p5";
const _fireworksBaseUrl = "https://api.fireworks.ai/inference/v1";
const _requestTimeout = Duration(seconds: 60);
const _maxRetries = 2;

typedef AgentRunResult = ({
  String? text,
  IList<String> writtenPaths,
  IList<String> toolsCalled,
  IList<String> capabilitiesRead,
});

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

class RunAgentLlm extends Fx<AgentRunResult?> {
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
  }) : super(() async {
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
            return await _runLoop(
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

Future<ChatCompletion> _requestWithTimeout(
  OpenAIClient client,
  ChatCompletionCreateRequest request,
  Logger logger,
  String agentId,
) async {
  for (var attempt = 0; attempt <= _maxRetries; attempt++) {
    try {
      return await client.chat.completions
          .create(request)
          .timeout(_requestTimeout);
    } on TimeoutException {
      logger.warning(
        "[$agentId] LLM request timed out "
        "(attempt ${attempt + 1}/${_maxRetries + 1})",
      );
      if (attempt == _maxRetries) {
        rethrow;
      }
    } on OpenAIException catch (e) {
      logger.warning(
        "[$agentId] LLM error: $e "
        "(attempt ${attempt + 1}/${_maxRetries + 1})",
      );
      if (attempt == _maxRetries) {
        rethrow;
      }
    }
  }
  throw TimeoutException(
    "LLM request failed after ${_maxRetries + 1} attempts",
  );
}

Future<AgentRunResult?> _runLoop({
  required OpenAIClient client,
  required List<ChatMessage> messages,
  required List<Tool> tools,
  required IList<AllowlistedTool> allowlist,
  required String vaultPath,
  required String telegramToken,
  required String tavilyToken,
  required Logger logger,
  required String agentId,
}) async {
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
      "[$agentId] LLM request "
      "(${current.length} messages)",
    );
    final response = await _requestWithTimeout(
      client,
      ChatCompletionCreateRequest(
        model: _model,
        messages: current,
        tools: tools,
      ),
      logger,
      agentId,
    );
    requestCount++;
    final usage = response.usage;
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
    final choice = response.choices.firstOrNull;
    if (choice == null) {
      logger.warning("[$agentId] Empty response from LLM");
      return null;
    }
    final message = choice.message;
    final toolCalls = message.toolCalls;

    // No tool calls — model returned text directly.
    if (toolCalls == null || toolCalls.isEmpty) {
      final raw = message.content?.trim() ?? "";
      // Fallback for models that route output to reasoning fields
      // (Kimi K2.5 sometimes produces only reasoning tokens after
      // heavy tool work, leaving content empty). Not ideal — the
      // text may read as "thinking aloud" — but it's better than
      // silent failure.
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
      // Surface explicit refusals as themselves rather than silently
      // dropping them.
      final refusal = message.refusal?.trim();
      final fromRefusal = refusal != null && refusal.isNotEmpty
          ? "(model refused) $refusal"
          : null;
      final text = effective.isEmpty ||
              effective.startsWith("(Empty response:")
          ? fromRefusal
          : effective;

      // Kimi K2.5 occasionally finishes a turn with no reply text
      // after doing real work — treats "I read/wrote the files" as
      // the response. For a Telegram user this looks like the bot
      // ignored them. One-shot harness-side nudge: ask the model to
      // send the reply it forgot. Fires at most once per turn,
      // whenever any tools were called (read-only retrieval or
      // write-side action both count).
      if (text == null && toolsCalled.isNotEmpty && !nudgedForReply) {
        logger.warning(
          "[$agentId] Silent finish with ${toolsCalled.length} "
          "tool call(s) — nudging once for a reply",
        );
        nudgedForReply = true;
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
        return (
          text: null,
          writtenPaths: const IList<String>.empty(),
          toolsCalled: toolsCalled.toIList(),
          capabilitiesRead: capabilitiesRead.toIList(),
        );
      }
      logger.debug(
        "[$agentId] Done — "
        "${writtenPaths.length} write(s), "
        "reply: ${text != null}",
      );
      return (
        text: text,
        writtenPaths: writtenPaths.toIList(),
        toolsCalled: toolsCalled.toIList(),
        capabilitiesRead: capabilitiesRead.toIList(),
      );
    }

    current = [
      ...current,
      ChatMessage.assistant(
        content: message.content,
        toolCalls: toolCalls,
      ),
    ];

    // Tool calls in a single LLM response are concurrent per the
    // OpenAI tool-calling protocol — the model knows it's
    // requesting parallel work. We parallelize them with
    // Future.wait, then append results in original call order so
    // the conversation history matches the model's expectation.
    // Trackers (toolsCalled, writtenPaths, capabilitiesRead) update
    // synchronously from the call args before launching, so they
    // see every call regardless of when it finishes.
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
      logger.debug(
        "[$agentId] Tool result [${call.function.name}]: "
        "${result.length > 200
            ? '${result.substring(0, 200)}...'
            : result}",
      );
      current = [
        ...current,
        ChatMessage.tool(
          toolCallId: call.id,
          content: result,
        ),
      ];
    }
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
