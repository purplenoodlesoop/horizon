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
