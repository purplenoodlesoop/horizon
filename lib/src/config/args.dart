import "dart:io";

import "package:args/args.dart";
import "package:fn/fn.dart";

import "package:horizon/src/config/config.dart";

final _parser = ArgParser()
  ..addOption(
    "env-file",
    defaultsTo: ".env",
    help: "Path to .env file with KEY=VALUE pairs (loaded before other flags)",
  )
  ..addOption(
    "telegram-token",
    help: "Telegram bot token (or TELEGRAM_TOKEN in env file)",
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
    help: "Fireworks.ai API token (or FIREWORKS_TOKEN in env file)",
  )
  ..addOption(
    "tavily-token",
    help: "Tavily search API token, optional (or TAVILY_TOKEN in env file)",
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
    help: r"Path to tool allowlist YAML. "
        r"Falls back to $HORIZON_ALLOWLIST, then ./config/allowlist.yaml.",
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
  ..addFlag("help", abbr: "h", negatable: false, help: "Show this help");

Map<String, String> _loadEnvFile(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    return {};
  }
  final env = <String, String>{};
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith("#")) {
      continue;
    }
    final eq = trimmed.indexOf("=");
    if (eq <= 0) {
      continue;
    }
    final key = trimmed.substring(0, eq).trim();
    var value = trimmed.substring(eq + 1).trim();
    // Strip optional surrounding quotes.
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}

class ParseArgs extends Fx<HorizonConfig> {
  ParseArgs(List<String> args)
    : super(() {
        final results = _parser.parse(args);
        if (results["help"] == true) {
          stdout.writeln(_parser.usage);
          exit(0);
        }

        final envFilePath = results["env-file"];
        final env = _loadEnvFile(
          envFilePath is String ? envFilePath : ".env",
        );

        String resolve(String flagName, String envKey) {
          final flag = results[flagName];
          if (flag is String && flag.isNotEmpty) {
            return flag;
          }
          return env[envKey] ?? Platform.environment[envKey] ?? "";
        }

        final telegramToken = resolve("telegram-token", "TELEGRAM_TOKEN");
        final fireworksToken = resolve("fireworks-token", "FIREWORKS_TOKEN");
        final tavilyToken = resolve("tavily-token", "TAVILY_TOKEN");
        final rawUsername = resolve("telegram-username", "TELEGRAM_USERNAME");
        final telegramUsername = rawUsername
            .replaceFirst(RegExp(r"^@"), "")
            .toLowerCase();

        if (telegramToken.isEmpty) {
          stderr.writeln(
            "Error: --telegram-token is required "
            "(or set TELEGRAM_TOKEN in .env)",
          );
          exit(1);
        }
        if (fireworksToken.isEmpty) {
          stderr.writeln(
            "Error: --fireworks-token is required "
            "(or set FIREWORKS_TOKEN in .env)",
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
        // For --allowlist and --templates, the resolution order is:
        // explicit flag → env var (HORIZON_ALLOWLIST / HORIZON_TEMPLATES)
        // → cwd-relative default. The Nix wrapper sets the env vars
        // to install-prefix paths so `nix run` works from any
        // directory.
        final allowlistPath = rawAllowlist is String && rawAllowlist.isNotEmpty
            ? rawAllowlist
            : (Platform.environment["HORIZON_ALLOWLIST"] ??
                "config/allowlist.yaml");
        final templatesPath = rawTemplates is String && rawTemplates.isNotEmpty
            ? rawTemplates
            : (Platform.environment["HORIZON_TEMPLATES"] ?? "templates");
        final heartbeatSeconds = rawHeartbeat is String
            ? int.tryParse(rawHeartbeat) ?? 300
            : 300;
        return HorizonConfig(
          telegramToken: telegramToken,
          telegramUsername: telegramUsername,
          fireworksToken: fireworksToken,
          tavilyToken: tavilyToken,
          vaultPath: vaultPath,
          mode: mode,
          allowlistPath: allowlistPath,
          templatesPath: templatesPath,
          heartbeatInterval: Duration(seconds: heartbeatSeconds),
        );
      });
}
