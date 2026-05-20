import "dart:io";

const _shellInterpreters = [
  "sh",
  "bash",
  "zsh",
  "python",
  "python3",
  "perl",
  "ruby",
  "node",
  "exec",
  "eval",
];

String shellEscape(String value) {
  final escaped = value.replaceAll("'", r"'\''");
  return "'$escaped'";
}

String? validatePath(String vaultPath, String argValue) {
  if (argValue.contains("..")) {
    return "Path traversal not allowed: $argValue";
  }
  final resolved = File("$vaultPath/$argValue").absolute.path;
  final vaultResolved = Directory(vaultPath).absolute.path;
  if (!resolved.startsWith(vaultResolved)) {
    return "Path outside vault: $argValue";
  }
  return null;
}

/// Files under `tasks/<ulid>/` that the Potentiality daemon and its
/// spawned Claude Code subagent own exclusively. The orchestrator
/// must not write to these — when pot's agent fails, having
/// `write_file` access to `findings.md` lets the orchestrator's LLM
/// rationalize fabricating the missing result and present it as
/// authoritative (observed 2026-05-20). The harness refuses these
/// writes structurally; prose-only "do not synthesize" rules don't
/// hold.
///
/// The orchestrator may still write `tasks/<id>/deliveries.yaml` and
/// `tasks/<id>/questions/<NNN>.notified` — those are the legit
/// orchestrator-owned bookkeeping files.
const _potTaskProtectedFilenames = {
  "task.md",
  "meta.yaml",
  "plan.md",
  "findings.md",
  "transcript.md",
  "transcript.jsonl",
};

/// Returns an error string if `argValue` is a write target the
/// orchestrator must not touch (pot-owned task content), null
/// otherwise. Called only for write-class tools (`write_file`,
/// `append_file`, `delete_file`).
String? validateTaskWrite(String argValue) {
  final parts = argValue.split("/");
  if (parts.length < 3) {
    return null;
  }
  if (parts[0] != "tasks") {
    return null;
  }
  final filename = parts.last;
  if (_potTaskProtectedFilenames.contains(filename)) {
    return "tasks/<id>/$filename is owned by the Potentiality daemon "
        "and its spawned agents. The orchestrator may only write "
        "deliveries.yaml and *.notified markers under tasks/<id>/. "
        "If pot's findings.md is missing, do not synthesize a "
        "replacement — tell the user the task ended without findings.";
  }
  return null;
}

String? validateCommand(String rendered) {
  final lower = rendered.toLowerCase();
  for (final interpreter in _shellInterpreters) {
    if (lower.contains("| $interpreter") ||
        lower.contains("|$interpreter")) {
      return "Pipe to shell interpreter not allowed: $interpreter";
    }
  }
  return null;
}

/// Returns the set of chat_ids that have ever sent us an accepted
/// inbound message (extracted from `_horizon/messages/*.md`
/// frontmatter). The send_telegram tool refuses to target any
/// chat_id outside this set — outbound is bounded by inbound.
Set<String> loadAllowedChatIds(String vaultPath) {
  final dir = Directory("$vaultPath/_horizon/messages");
  if (!dir.existsSync()) {
    return const {};
  }
  final pattern = RegExp(r"^chat_id:\s*(\S+)\s*$", multiLine: true);
  final ids = <String>{};
  for (final entity in dir.listSync()) {
    if (entity is! File || !entity.path.endsWith(".md")) {
      continue;
    }
    final content = entity.readAsStringSync();
    for (final match in pattern.allMatches(content)) {
      ids.add(match.group(1)!);
    }
  }
  return ids;
}
