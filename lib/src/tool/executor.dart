import "dart:convert";
import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";

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
    required String telegramToken,
    required String tavilyToken,
  }) : super(() async {
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
          final result = await Process.run(
            "bash",
            ["-c", rendered],
            stdoutEncoding: utf8,
            stderrEncoding: utf8,
            environment: {
              ...Platform.environment,
              if (telegramToken.isNotEmpty) "TELEGRAM_TOKEN": telegramToken,
              if (tavilyToken.isNotEmpty) "TAVILY_TOKEN": tavilyToken,
            },
            includeParentEnvironment: false,
          );
          final out = result.stdout;
          final err = result.stderr;
          final outStr = out is String ? out : "";
          final errStr = err is String ? err : "";
          if (result.exitCode != 0 && errStr.isNotEmpty) {
            return "Error (exit ${result.exitCode}): $errStr";
          }
          return outStr.isNotEmpty ? outStr : "(no output)";
        });
}
