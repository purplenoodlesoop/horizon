import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";

/// Mutable in-memory env-var store. Source of truth at runtime for
/// rotatable secrets (`TELEGRAM_TOKEN`, `LLM_TOKEN`, `TAVILY_TOKEN`,
/// …) and the LLM endpoint config (`LLM_URL`, `LLM_MODEL`).
/// Initially populated from the `.env` file merged over
/// `Platform.environment`. Watched by `WatchEnvFile`, which calls
/// `reload()` on change so rotation takes effect without a restart.
class EnvStore {
  EnvStore._({required this.envFilePath, required Map<String, String> initial})
      : _values = Map.of(initial);

  factory EnvStore.load({required String envFilePath}) =>
      EnvStore._(envFilePath: envFilePath, initial: parseEnvFile(envFilePath));

  final String envFilePath;
  Map<String, String> _values;

  /// Resolution order: env file > process env > empty.
  String get(String key) =>
      _values[key] ?? Platform.environment[key] ?? "";

  String get telegramToken => get("TELEGRAM_TOKEN");
  String get llmToken => get("LLM_TOKEN");

  /// Defaults to CrofAI's OpenAI-compatible endpoint. Override via
  /// `LLM_URL` (env or `--llm-url`) to point at any other provider.
  String get llmUrl {
    final v = get("LLM_URL");
    return v.isEmpty ? "https://crof.ai/v1" : v;
  }

  /// Defaults to Kimi K2.6 (MoonshotAI) as exposed by CrofAI. Override
  /// via `LLM_MODEL` (env or `--llm-model`). When you change `LLM_URL`
  /// you almost always need to change `LLM_MODEL` too — model ids are
  /// provider-specific (e.g. `accounts/fireworks/models/kimi-k2p5` on
  /// Fireworks vs `kimi-k2.6` on CrofAI).
  String get llmModel {
    final v = get("LLM_MODEL");
    return v.isEmpty ? "kimi-k2.6" : v;
  }

  String get tavilyToken => get("TAVILY_TOKEN");

  /// Set of allowed Telegram usernames (each with optional leading
  /// `@` stripped and lowercased). `TELEGRAM_USERNAME` may be a
  /// single username or a comma- / whitespace-separated list, so
  /// existing single-user configs keep working.
  ///
  /// Empty set means fail-closed: inbound is dropped, outbound is
  /// bounded to chat_ids that have already DM'd the bot.
  Set<String> get telegramUsernames {
    final raw = get("TELEGRAM_USERNAME");
    if (raw.isEmpty) {
      return const {};
    }
    return raw
        .split(RegExp(r"[,\s]+"))
        .map((u) => u.trim().replaceFirst(RegExp(r"^@"), "").toLowerCase())
        .where((u) => u.isNotEmpty)
        .toSet();
  }

  /// Backward-compat shim — empty when no usernames configured,
  /// otherwise the first configured username (mostly useful for log
  /// lines that want a single value).
  String get telegramUsername {
    final s = telegramUsernames;
    return s.isEmpty ? "" : s.first;
  }

  /// Snapshot of the current env-file map (Platform.environment is
  /// not included). Useful for passing to subprocesses.
  IMap<String, String> envFileSnapshot() => _values.lock;

  /// Apply a startup-time flag override that takes precedence over
  /// the env file. Stored in the same map so reload() compares
  /// against this flag-augmented baseline. The override is preserved
  /// across reloads — if the env file later sets the same key to a
  /// different value, the file wins (next reload), so flags really
  /// are only "initial overrides" and the long-lived source of truth
  /// is the file.
  void applyOverride(String key, String value) {
    _values[key] = value;
  }

  /// Re-parse the env file. Returns the diff against the previous
  /// snapshot, or null if nothing changed.
  EnvDiff? reload() {
    final newValues = parseEnvFile(envFilePath);
    final old = _values;
    final added = <String>[];
    final removed = <String>[];
    final changed = <String, ({int oldLen, int newLen})>{};
    for (final e in newValues.entries) {
      if (!old.containsKey(e.key)) {
        added.add(e.key);
      } else if (old[e.key] != e.value) {
        changed[e.key] = (oldLen: old[e.key]!.length, newLen: e.value.length);
      }
    }
    for (final k in old.keys) {
      if (!newValues.containsKey(k)) {
        removed.add(k);
      }
    }
    if (added.isEmpty && removed.isEmpty && changed.isEmpty) {
      return null;
    }
    _values = newValues;
    return EnvDiff(added: added, removed: removed, changed: changed);
  }
}

/// Redacted summary of an env-file reload. Values are never logged;
/// only key names + length deltas. Designed to be safe to print on
/// the console and persist in the file logger.
class EnvDiff {
  const EnvDiff({
    required this.added,
    required this.removed,
    required this.changed,
  });

  final List<String> added;
  final List<String> removed;
  final Map<String, ({int oldLen, int newLen})> changed;

  bool get isEmpty =>
      added.isEmpty && removed.isEmpty && changed.isEmpty;

  /// One-line summary, e.g.
  /// `Env reload: added [FOO], changed [TAVILY_TOKEN (12→14 chars)]`.
  String summarize() {
    final parts = <String>[];
    if (added.isNotEmpty) {
      parts.add("added [${added.join(", ")}]");
    }
    if (changed.isNotEmpty) {
      final pieces = changed.entries.map(
        (e) => "${e.key} (${e.value.oldLen}→${e.value.newLen} chars)",
      );
      parts.add("changed [${pieces.join(", ")}]");
    }
    if (removed.isNotEmpty) {
      parts.add("removed [${removed.join(", ")}]");
    }
    return "Env reload: ${parts.join("; ")}";
  }

  /// True when a key whose change requires more than passing the new
  /// value to the next subprocess — e.g. `TELEGRAM_TOKEN` /
  /// `TELEGRAM_USERNAME` need the poller restarted.
  bool affectsTelegramConnection() =>
      added.contains("TELEGRAM_TOKEN") ||
      removed.contains("TELEGRAM_TOKEN") ||
      changed.containsKey("TELEGRAM_TOKEN") ||
      added.contains("TELEGRAM_USERNAME") ||
      removed.contains("TELEGRAM_USERNAME") ||
      changed.containsKey("TELEGRAM_USERNAME");
}

/// Parses a KEY=VALUE env file. Lines with `#` or empty lines are
/// ignored. Values may be optionally surrounded by single or double
/// quotes; quotes are stripped. Missing file → empty map.
Map<String, String> parseEnvFile(String path) {
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
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      value = value.substring(1, value.length - 1);
    }
    env[key] = value;
  }
  return env;
}
