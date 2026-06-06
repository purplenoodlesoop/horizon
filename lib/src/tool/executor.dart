import "dart:convert";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";

import "package:horizon/src/config/env_store.dart";
import "package:horizon/src/tool/allowlist.dart";
import "package:horizon/src/tool/security.dart";

String _renderTemplate(
  String template,
  String vaultPath,
  String telegramToken,
  IMap<String, String> args,
) {
  var result = template.replaceAll(
    "{vault_path}",
    shellEscape(vaultPath),
  );
  result = result.replaceAll(
    "{telegram_token}",
    shellEscape(telegramToken),
  );
  for (final entry in args.entries) {
    result = result.replaceAll(
      "{${entry.key}}",
      shellEscape(entry.value),
    );
  }
  return result;
}

class ExecuteTool extends Fx<String> {
  ExecuteTool({
    required IList<AllowlistedTool> allowlist,
    required String toolName,
    required IMap<String, String> toolArgs,
    required String vaultPath,
    required EnvStore envStore,
    String? currentChatId,
  }) : super(() async {
          // Snapshot tokens at execution start. The executor reads
          // them via envStore so live `.env` rotation takes effect on
          // the next tool call without restarting the harness.
          final telegramToken = envStore.telegramToken;
          final tavilyToken = envStore.tavilyToken;
          final chatId = currentChatId;
          final tool = allowlist
              .where((t) => t.name == toolName)
              .firstOrNull;
          if (tool == null) {
            return "Error: tool '$toolName' is not in the allowlist";
          }
          for (final paramName in tool.parameters.keys) {
            final argValue = toolArgs[paramName];
            if (argValue == null) {
              return "Error: missing required argument '$paramName'";
            }
            final param = tool.parameters[paramName];
            if (param != null &&
                (param.type == "path" || paramName.contains("path"))) {
              final pathError = validatePath(vaultPath, argValue);
              if (pathError != null) {
                return "Error: $pathError";
              }
              // Structural block: writes / deletes to pot-task-owned
              // files (findings.md, transcript.*, task.md, plan.md,
              // meta.yaml under tasks/<id>/) are reserved for the
              // Potentiality daemon and its spawned agents. The
              // orchestrator cannot write these even if its capability
              // prose suggests "deliver the result." See
              // validateTaskWrite for the rationale.
              if (toolName == "write_file" ||
                  toolName == "append_file" ||
                  toolName == "delete_file") {
                final writeError = validateTaskWrite(argValue);
                if (writeError != null) {
                  return "Error: $writeError";
                }
              }
            }
            if (param != null && param.type == "telegram_chat_id") {
              final allowed = loadAllowedChatIds(vaultPath);
              if (!allowed.contains(argValue)) {
                return "Error: chat_id '$argValue' has never sent us "
                    "an accepted message. Outbound Telegram is bounded "
                    "to chat_ids present in _horizon/messages/.";
              }
            }
          }
          final rendered = _renderTemplate(
            tool.commandTemplate,
            vaultPath,
            telegramToken,
            toolArgs,
          );
          final commandError = validateCommand(rendered);
          if (commandError != null) {
            return "Error: $commandError";
          }
          // Pass secret tokens via environment variables, not via
          // command-line substitution — keeps them out of process
          // listings and the rendered template string.
          // stdoutEncoding: null returns raw bytes so we can recover
          // gracefully from binary output (e.g. `cat` on a PDF). With
          // any encoding here (defaults to systemEncoding == utf8), a
          // single non-UTF-8 byte raises FormatException out of
          // Process.run and tears down the pipeline.
          final result = await Process.run(
            "bash",
            ["-c", rendered],
            stdoutEncoding: null,
            stderrEncoding: utf8,
            environment: {
              ...Platform.environment,
              if (telegramToken.isNotEmpty) "TELEGRAM_TOKEN": telegramToken,
              if (tavilyToken.isNotEmpty) "TAVILY_TOKEN": tavilyToken,
              // D8: the chat the agent is talking in (telegram turns only).
              // Lets schedule_* resolve `deliver: origin`/blank to this chat,
              // so a reminder created here is never a silent black hole.
              if (chatId != null && chatId.isNotEmpty)
                "HORIZON_CHAT_ID": chatId,
            },
            includeParentEnvironment: false,
          );
          final out = result.stdout;
          final err = result.stderr;
          final errStr = err is String ? err : "";
          String outStr;
          if (out is List<int>) {
            try {
              outStr = utf8.decode(out);
            } on FormatException {
              outStr = "(binary output: ${out.length} bytes — this tool's "
                  "output is not UTF-8 text. For binary files like PDFs "
                  "or images use a tool that converts them to text first.)";
            }
          } else if (out is String) {
            outStr = out;
          } else {
            outStr = "";
          }
          if (result.exitCode != 0 && errStr.isNotEmpty) {
            return "Error (exit ${result.exitCode}): $errStr";
          }
          return outStr.isNotEmpty ? outStr : "(no output)";
        });
}
