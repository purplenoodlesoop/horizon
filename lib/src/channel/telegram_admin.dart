import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/config/env_store.dart";
import "package:horizon/src/config/preferences.dart";
import "package:mark/mark.dart";

/// Pre-LLM Telegram admin commands. The harness intercepts known
/// `/`-prefixed messages BEFORE constructing the orchestrator event,
/// so the orchestrator never sees these. Unknown prefixes fall
/// through to the orchestrator (so the user can still ask
/// "tell me about /banana").
///
/// Grammar is fixed and frozen — adding a command requires a
/// roadmap entry, not improvisation. See `spec/phase-7-plan.md` §7.7.

sealed class AdminCommand {
  const AdminCommand();
}

final class PromoteCmd extends AdminCommand {
  PromoteCmd(this.id);
  final String id;
}

final class DemoteCmd extends AdminCommand {
  DemoteCmd(this.id);
  final String id;
}

final class ListProposedCmd extends AdminCommand {
  const ListProposedCmd();
}

final class QuietCmd extends AdminCommand {
  const QuietCmd();
}

final class LoudCmd extends AdminCommand {
  const LoudCmd();
}

final class VersionCmd extends AdminCommand {
  const VersionCmd();
}

final class DiffCmd extends AdminCommand {
  DiffCmd(this.id);
  final String id;
}

final class HelpCmd extends AdminCommand {
  const HelpCmd();
}

final class MalformedAdminCmd extends AdminCommand {
  MalformedAdminCmd({required this.command, required this.usage});
  final String command;
  final String usage;
}

/// Parses admin commands. Returns null when the input is not a
/// recognized admin prefix (the harness then forwards to the
/// orchestrator). Returns `MalformedAdminCmd` when a known command
/// has the wrong argument shape — the user gets a usage error and
/// the LLM still doesn't see the message.
AdminCommand? parseAdminCommand(String text) {
  final trimmed = text.trim();
  if (!trimmed.startsWith("/")) {
    return null;
  }
  final parts = trimmed.split(RegExp(r"\s+"));
  final cmd = parts[0];
  switch (cmd) {
    case "/promote":
      if (parts.length != 2) {
        return MalformedAdminCmd(
          command: "/promote",
          usage: "Usage: /promote &lt;id&gt;",
        );
      }
      return PromoteCmd(parts[1]);
    case "/demote":
      if (parts.length != 2) {
        return MalformedAdminCmd(
          command: "/demote",
          usage: "Usage: /demote &lt;id&gt;",
        );
      }
      return DemoteCmd(parts[1]);
    case "/proposed":
      return const ListProposedCmd();
    case "/quiet":
      return const QuietCmd();
    case "/loud":
      return const LoudCmd();
    case "/version":
      return const VersionCmd();
    case "/diff":
      if (parts.length != 2) {
        return MalformedAdminCmd(
          command: "/diff",
          usage: "Usage: /diff &lt;id&gt;",
        );
      }
      return DiffCmd(parts[1]);
    case "/help":
      return const HelpCmd();
    default:
      return null;
  }
}

/// Executes a parsed admin command. Returns the reply text (already
/// HTML-escaped where needed for Telegram). Mutating commands also
/// write an entry to `_horizon/admin-log/<YYYY-MM>.md` and, when the
/// vault is a git repo, commit the change.
class ExecuteAdminCommand extends Fx<String> {
  ExecuteAdminCommand({
    required AdminCommand command,
    required String vaultPath,
    required EnvStore envStore,
    required Logger logger,
  }) : super(() async {
          final result = await _dispatch(
            command: command,
            vaultPath: vaultPath,
            envStore: envStore,
            logger: logger,
          );
          if (result.auditLine != null) {
            _appendAuditLog(vaultPath, result.auditLine!);
          }
          return result.reply;
        });
}

class _AdminResult {
  const _AdminResult({required this.reply, this.auditLine});
  final String reply;
  final String? auditLine;
}

Future<_AdminResult> _dispatch({
  required AdminCommand command,
  required String vaultPath,
  required EnvStore envStore,
  required Logger logger,
}) async => switch (command) {
      PromoteCmd(:final id) => await _movePromotion(
          vaultPath: vaultPath,
          id: id,
          direction: _PromotionDir.promote,
          logger: logger,
        ),
      DemoteCmd(:final id) => await _movePromotion(
          vaultPath: vaultPath,
          id: id,
          direction: _PromotionDir.demote,
          logger: logger,
        ),
      ListProposedCmd() => _AdminResult(reply: _listProposed(vaultPath)),
      QuietCmd() => await _setStreamUi(vaultPath: vaultPath, on: false),
      LoudCmd() => await _setStreamUi(vaultPath: vaultPath, on: true),
      VersionCmd() => _AdminResult(reply: _version(vaultPath)),
      DiffCmd(:final id) =>
          _AdminResult(reply: _diff(vaultPath: vaultPath, id: id)),
      HelpCmd() => const _AdminResult(reply: _helpText),
      MalformedAdminCmd(:final command, :final usage) =>
          _AdminResult(reply: "<b>$command</b>\n$usage"),
    };

enum _PromotionDir { promote, demote }

Future<_AdminResult> _movePromotion({
  required String vaultPath,
  required String id,
  required _PromotionDir direction,
  required Logger logger,
}) async {
  if (!_isSafeId(id)) {
    return _AdminResult(
      reply: "Refused: id <code>$id</code> is not safe (must match "
          "<code>[a-z0-9-]+</code>).",
    );
  }
  final canonical = "$vaultPath/_horizon/capabilities/$id.md";
  final proposed = "$vaultPath/_horizon/capabilities/proposed/$id.md";
  final fromPath = direction == _PromotionDir.promote ? proposed : canonical;
  final toPath = direction == _PromotionDir.promote ? canonical : proposed;
  final fromFile = File(fromPath);
  if (!fromFile.existsSync()) {
    final fromKind =
        direction == _PromotionDir.promote ? "proposed" : "active";
    return _AdminResult(
      reply: "Refused: <code>$id</code> not found among $fromKind "
          "capabilities.",
    );
  }
  final toFile = File(toPath);
  await toFile.parent.create(recursive: true);
  await fromFile.rename(toFile.path);
  final verb = direction == _PromotionDir.promote ? "Promoted" : "Demoted";
  final commitMsg = "horizon: ${verb.toLowerCase()} $id";
  final commit = await _maybeGitCommit(vaultPath, commitMsg, [
    fromPath,
    toPath,
  ], logger);
  final commitTag = commit != null ? " (commit ${commit.substring(0, 7)})" : "";
  return _AdminResult(
    reply: "$verb <code>$id</code>$commitTag.",
    auditLine: "${_nowIso()} $verb $id$commitTag",
  );
}

String _listProposed(String vaultPath) {
  final dir = Directory("$vaultPath/_horizon/capabilities/proposed");
  if (!dir.existsSync()) {
    return "(no proposals — directory does not exist)";
  }
  final ids = <String>[];
  for (final entity in dir.listSync()) {
    if (entity is File && entity.path.endsWith(".md")) {
      final basename = entity.uri.pathSegments.last;
      ids.add(basename.substring(0, basename.length - 3));
    }
  }
  if (ids.isEmpty) {
    return "(no proposed capabilities)";
  }
  ids.sort();
  return "<b>Proposed capabilities</b>\n${ids.map((i) => "• <code>$i</code>").join("\n")}";
}

Future<_AdminResult> _setStreamUi({
  required String vaultPath,
  required bool on,
}) async {
  final current = await LoadPreferences(
    vaultPath: vaultPath,
    fallback: const Preferences(),
  );
  final next = current.copyWith(streamUi: on);
  await SavePreferences(vaultPath: vaultPath, preferences: next);
  final state = on ? "on" : "off";
  return _AdminResult(
    reply: "Streaming UI: <b>$state</b>.",
    auditLine: "${_nowIso()} stream_ui=$state",
  );
}

String _version(String vaultPath) {
  final commit = _gitHead(vaultPath: ".") ?? "(not a git checkout)";
  final vaultGit = _gitHead(vaultPath: vaultPath);
  final vaultLine =
      vaultGit != null ? "vault commit: <code>$vaultGit</code>" : "vault: not git-tracked";
  return [
    "<b>Horizon</b>",
    "code commit: <code>$commit</code>",
    "vault: <code>$vaultPath</code>",
    vaultLine,
  ].join("\n");
}

String _diff({required String vaultPath, required String id}) {
  if (!_isSafeId(id)) {
    return "Refused: id <code>$id</code> is not safe.";
  }
  final canonical = File("$vaultPath/_horizon/capabilities/$id.md");
  final proposed = File("$vaultPath/_horizon/capabilities/proposed/$id.md");
  if (!proposed.existsSync()) {
    return "<code>$id</code>: no proposed version.";
  }
  if (!canonical.existsSync()) {
    return "<code>$id</code>: new capability, no existing version.";
  }
  final result = Process.runSync("diff", [
    "-u",
    canonical.path,
    proposed.path,
  ]);
  final raw = (result.stdout is String ? result.stdout as String : "").trim();
  if (raw.isEmpty) {
    return "<code>$id</code>: identical.";
  }
  final escaped = _htmlEscape(raw);
  // Telegram caps at 4096 chars; pre tag adds ~11.
  const limit = 4000;
  final truncated = escaped.length > limit
      ? "${escaped.substring(0, limit)}\n…(truncated)"
      : escaped;
  return "<pre>$truncated</pre>";
}

// Telegram auto-links bare `/foo` patterns to tappable command chips —
// but only when they're NOT inside <code>/<pre> blocks. Keep command
// names plain so the user can tap them; format args/values separately.
const _helpText = '''
<b>Horizon admin commands</b>
/promote <i>id</i> — move proposed/&lt;id&gt;.md → capabilities/&lt;id&gt;.md
/demote <i>id</i> — reverse of promote
/proposed — list capability proposals
/diff <i>id</i> — diff proposed vs active version
/quiet — disable streaming "Thinking..." UI
/loud — enable streaming UI
/version — show commit hashes / vault path
/help — this message
''';

bool _isSafeId(String id) {
  if (id.isEmpty || id.length > 100) {
    return false;
  }
  return RegExp(r"^[a-z0-9][a-z0-9_-]*$").hasMatch(id);
}

String _nowIso() => DateTime.now().toUtc().toIso8601String();

String? _gitHead({required String vaultPath}) {
  final dir = Directory(vaultPath);
  if (!dir.existsSync()) {
    return null;
  }
  final result = Process.runSync(
    "git",
    ["-C", vaultPath, "rev-parse", "--short=12", "HEAD"],
  );
  if (result.exitCode != 0) {
    return null;
  }
  return (result.stdout as String).trim();
}

/// Returns the new commit hash on success, null if the vault isn't a
/// git repo or the commit failed (we still log the rename either
/// way; git is best-effort traceability, not gating).
Future<String?> _maybeGitCommit(
  String vaultPath,
  String message,
  List<String> paths,
  Logger logger,
) async {
  final dotGit = Directory("$vaultPath/.git");
  if (!dotGit.existsSync()) {
    return null;
  }
  final relativePaths = paths
      .map((p) => p.startsWith("$vaultPath/")
          ? p.substring(vaultPath.length + 1)
          : p)
      .toList();
  final add = await Process.run(
    "git",
    ["-C", vaultPath, "add", ...relativePaths],
  );
  if (add.exitCode != 0) {
    logger.warning(
      "Admin: git add failed (${add.exitCode}): ${add.stderr}",
    );
    return null;
  }
  final commit = await Process.run(
    "git",
    ["-C", vaultPath, "commit", "-m", message],
  );
  if (commit.exitCode != 0) {
    logger.warning(
      "Admin: git commit failed (${commit.exitCode}): ${commit.stderr}",
    );
    return null;
  }
  final head = await Process.run(
    "git",
    ["-C", vaultPath, "rev-parse", "--short=7", "HEAD"],
  );
  if (head.exitCode != 0) {
    return null;
  }
  return (head.stdout as String).trim();
}

void _appendAuditLog(String vaultPath, String line) {
  final now = DateTime.now().toUtc();
  final yyyymm =
      "${now.year}-${now.month.toString().padLeft(2, "0")}";
  final dir = Directory("$vaultPath/_horizon/admin-log")
    ..createSync(recursive: true);
  File("${dir.path}/$yyyymm.md")
      .writeAsStringSync("- $line\n", mode: FileMode.append);
}

String _htmlEscape(String s) => s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");
