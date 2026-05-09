import "dart:io";

import "package:args/args.dart";
import "package:fn/fn.dart";

import "package:horizon/src/config/config.dart";
import "package:horizon/src/config/env_store.dart";

final _parser = ArgParser()
  ..addOption(
    "env-file",
    defaultsTo: ".env",
    help: "Path to .env file with KEY=VALUE pairs (loaded before other flags)",
  )
  ..addOption(
    "telegram-token",
    help: "Telegram bot token (overrides TELEGRAM_TOKEN in env file)",
  )
  ..addOption(
    "telegram-username",
    help: "Telegram username allowed to interact (without @). The "
        "bot ignores messages from any other username and refuses to "
        "send to chat_ids that have not sent us an accepted message. "
        "Or set TELEGRAM_USERNAME in env file.",
  )
  ..addOption(
    "fireworks-token",
    help: "Fireworks.ai API token (overrides FIREWORKS_TOKEN in env file)",
  )
  ..addOption(
    "tavily-token",
    help: "Tavily search API token, optional "
        "(overrides TAVILY_TOKEN in env file)",
  )
  ..addOption(
    "vault",
    defaultsTo: "vault",
    help: "Path to the Obsidian vault directory",
  )
  ..addOption(
    "mode",
    defaultsTo: "human",
    allowed: ["human", "agent"],
    help: "Operating mode: human or agent",
  )
  ..addOption(
    "allowlist",
    help: r"Path to tool allowlist YAML. Override; if unset, the "
        r"harness reads from <vault>/_horizon/system/allowlist.yaml "
        r"(bootstrapped from templates on first run). $HORIZON_ALLOWLIST "
        r"is honored as a secondary override.",
  )
  ..addOption(
    "templates",
    help: r"Path to default capability templates (used on first run "
        r"to bootstrap an empty vault). "
        r"Falls back to $HORIZON_TEMPLATES, then ./templates.",
  )
  ..addOption(
    "heartbeat",
    defaultsTo: "3600",
    help: "Heartbeat interval in seconds",
  )
  ..addOption(
    "telegram-stream-ui",
    defaultsTo: "on",
    allowed: ["on", "off"],
    help: "Stream intermediate 'Thinking' / per-tool status edits to "
        "Telegram during long turns. 'off' sends only the final reply "
        "(typing indicator still shown). Vault-level override: "
        "stream_ui field in _horizon/system/preferences.md.",
  )
  ..addFlag("help", abbr: "h", negatable: false, help: "Show this help");

class ParseArgs extends Fx<({HorizonConfig config, EnvStore envStore})> {
  ParseArgs(List<String> args)
    : super(() {
        final results = _parser.parse(args);
        if (results["help"] == true) {
          stdout.writeln(_parser.usage);
          exit(0);
        }

        final envFilePath = results["env-file"];
        final envFilePathStr =
            envFilePath is String ? envFilePath : ".env";

        // Build the live env store. Flags layer on top of the file
        // (and process env, which the store reads as a fallback).
        final envStore = EnvStore.load(envFilePath: envFilePathStr);
        _applyFlagOverride(
          results,
          "telegram-token",
          envStore,
          "TELEGRAM_TOKEN",
        );
        _applyFlagOverride(
          results,
          "telegram-username",
          envStore,
          "TELEGRAM_USERNAME",
        );
        _applyFlagOverride(
          results,
          "fireworks-token",
          envStore,
          "FIREWORKS_TOKEN",
        );
        _applyFlagOverride(results, "tavily-token", envStore, "TAVILY_TOKEN");

        if (envStore.telegramToken.isEmpty) {
          stderr.writeln(
            "Error: TELEGRAM_TOKEN is required (set --telegram-token, or "
            "TELEGRAM_TOKEN in .env)",
          );
          exit(1);
        }
        if (envStore.fireworksToken.isEmpty) {
          stderr.writeln(
            "Error: FIREWORKS_TOKEN is required (set --fireworks-token, or "
            "FIREWORKS_TOKEN in .env)",
          );
          exit(1);
        }

        final rawMode = results["mode"];
        final mode = rawMode is String && rawMode == "agent"
            ? const AgentMode(())
            : const HumanMode(());
        final rawVault = results["vault"];
        final rawAllowlist = results["allowlist"];
        final rawTemplates = results["templates"];
        final rawHeartbeat = results["heartbeat"];
        final vaultPath =
            rawVault is String ? rawVault : Directory.current.path;
        // --allowlist (or HORIZON_ALLOWLIST env) is now an OVERRIDE.
        // When unset, the harness reads from
        // <vault>/_horizon/system/allowlist.yaml on every event,
        // falling back to <templates>/_horizon/system/allowlist.yaml
        // until the vault is bootstrapped. Empty string = no override.
        final allowlistOverride =
            rawAllowlist is String && rawAllowlist.isNotEmpty
                ? rawAllowlist
                : (Platform.environment["HORIZON_ALLOWLIST"] ?? "");
        final templatesPath = rawTemplates is String && rawTemplates.isNotEmpty
            ? rawTemplates
            : (Platform.environment["HORIZON_TEMPLATES"] ?? "templates");
        final heartbeatSeconds = rawHeartbeat is String
            ? int.tryParse(rawHeartbeat) ?? 300
            : 300;
        final rawStreamUi = results["telegram-stream-ui"];
        final streamUi = rawStreamUi is! String || rawStreamUi != "off";
        final config = HorizonConfig(
          vaultPath: vaultPath,
          mode: mode,
          allowlistOverride: allowlistOverride,
          templatesPath: templatesPath,
          heartbeatInterval: Duration(seconds: heartbeatSeconds),
          streamUi: streamUi,
          envFilePath: envFilePathStr,
        );
        return (config: config, envStore: envStore);
      });
}

void _applyFlagOverride(
  ArgResults results,
  String flagName,
  EnvStore store,
  String envKey,
) {
  final raw = results[flagName];
  if (raw is! String || raw.isEmpty) {
    return;
  }
  // Mutate the store's underlying map via reload-style application:
  // we re-export the parsed env and merge the flag, then call reload
  // — but reload only reads from the file. Instead, just write into
  // the store via a small helper.
  store.applyOverride(envKey, raw);
}
