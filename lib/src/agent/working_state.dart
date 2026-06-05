import "dart:io";

import "package:fast_immutable_collections/fast_immutable_collections.dart";
import "package:fn/fn.dart";
import "package:horizon/src/config/env_store.dart";
import "package:mark/mark.dart";
import "package:openai_dart/openai_dart.dart";

const _stateSubdir = "_horizon/state";
const _stateFile = "working.md";

String workingStatePath(String vaultPath) =>
    "$vaultPath/$_stateSubdir/$_stateFile";

/// Reads the persistent, always-loaded working memory for this vault.
///
/// This document is injected into the orchestrator's context on EVERY
/// turn (see `centralized.dart`). It is the integrated, continuously
/// reconciled understanding the assistant acts from — never a file the
/// model has to choose to retrieve. Returns "" on cold start (no file).
class LoadWorkingState extends Fx<String> {
  LoadWorkingState({required String vaultPath})
      : super(() {
          final file = File(workingStatePath(vaultPath));
          if (!file.existsSync()) {
            return "";
          }
          return file.readAsStringSync().trim();
        });
}

const _digestSystemPrompt = '''
You are the memory-consolidation process for a personal assistant.
You maintain ONE compact, always-current "working memory" document that
is injected into the assistant's context on EVERY turn. The assistant
acts directly from this document — it is not optional background, it is
the ground the assistant relies on. Your job is to keep it true and
current by integrating the latest turn.

You receive the current working memory and a record of the latest turn
(what the user said, what the assistant replied, and which tools were
called with whether each SUCCEEDED or FAILED).

Rewrite the working memory so it integrates the latest turn. Rules:
- Output ONLY the new working-memory markdown. No preamble, no code fences.
- Integrate, do not append-log. Fold each new fact into the right place.
- Resolve contradictions: newest information wins; DELETE what it
  overrode. Never keep two conflicting statements side by side.
- Keep durable things only: who the user is; identity the user has
  established about the assistant (name, gender/grammatical gender, how
  to be addressed, tone/persona); standing preferences and directives;
  important facts about people and projects; and currently-open threads
  (questions awaiting an answer, tasks in progress).
- Record OUTCOMES, not intentions. If a tool FAILED, record that the
  action did NOT happen. NEVER record a failed or impossible action as done.
- Drop transient chit-chat and anything now stale or resolved.
- Keep it tight — under ~250 lines. Compress aggressively.
- Do NOT invent anything. Record only what the interaction established.
  If the current memory is empty and the turn established nothing
  durable, return the memory essentially unchanged (or empty).

Suggested structure (omit any empty section):
## Identity (who the assistant is, as the user established it)
## User
## People & projects
## Standing directives & preferences
## Open threads
## Recent outcomes
''';

/// Consolidates the latest turn into the persistent working memory via a
/// single non-streaming LLM call, then writes it back to disk.
///
/// Best-effort and self-contained: it constructs its own LLM client from
/// the env snapshot, and the caller is expected to guard the await so a
/// digestion failure never breaks the reply path.
class DigestWorkingState extends Fx<void> {
  DigestWorkingState({
    required EnvStore envStore,
    required String vaultPath,
    required String priorState,
    required String inbound,
    required String? reply,
    required IList<String> toolOutcomes,
    required Logger logger,
  }) : super(() async {
          final turn = StringBuffer()
            ..writeln("### User said")
            ..writeln(inbound.trim().isEmpty ? "(nothing)" : inbound.trim())
            ..writeln()
            ..writeln("### Assistant replied")
            ..writeln(
              (reply ?? "").trim().isEmpty ? "(no reply)" : reply!.trim(),
            );
          if (toolOutcomes.isNotEmpty) {
            turn
              ..writeln()
              ..writeln("### Tools called this turn (with outcome)");
            for (final t in toolOutcomes) {
              turn.writeln("- $t");
            }
          }

          final userMsg = StringBuffer()
            ..writeln("## Current working memory")
            ..writeln(
              priorState.trim().isEmpty
                  ? "(empty — cold start)"
                  : priorState.trim(),
            )
            ..writeln()
            ..writeln("## Latest turn to integrate")
            ..writeln(turn.toString().trimRight());

          final client = OpenAIClient.withApiKey(
            envStore.llmToken,
            baseUrl: envStore.llmUrl,
          );
          try {
            final res = await client.chat.completions.create(
              ChatCompletionCreateRequest(
                model: envStore.llmModel,
                messages: [
                  ChatMessage.system(_digestSystemPrompt),
                  ChatMessage.user(userMsg.toString()),
                ],
              ),
            );
            final next = res.choices.firstOrNull?.message.content?.trim();
            if (next == null || next.isEmpty) {
              logger.warning(
                "[digest] empty consolidation result — keeping prior state",
              );
              return;
            }
            final file = File(workingStatePath(vaultPath));
            file.parent.createSync(recursive: true);
            file.writeAsStringSync("$next\n");
            logger.debug(
              "[digest] working memory updated (${next.length} chars)",
            );
          } finally {
            client.close();
          }
        });
}

const _dreamSystemPrompt = '''
You are the dreaming process for a personal assistant — the deep,
from-scratch memory consolidation that runs on request when the
incremental digest has drifted, gone stale, or needs a clean reset.

You are given the assistant's long-term memory: its notes, people files,
journal, knowledge base, and recent conversations. From ALL of it,
SYNTHESISE — from scratch — the single "working memory" document that is
injected into the assistant's context on every turn and that it acts
directly from.

Rules:
- Output ONLY the working-memory markdown. No preamble, no code fences.
- Synthesise across everything; do NOT copy files verbatim. Compress hard.
- Resolve contradictions: the most recent / most explicit statement wins.
  Keep only the resolved truth, never two conflicting versions.
- Record OUTCOMES, not intentions. If the record shows an action failed
  or was impossible, never record it as done.
- Keep durable things only: who the user is; identity the user has
  established about the assistant (name, gender/grammatical gender, how
  to be addressed, tone/persona); standing preferences and directives;
  important facts about people and projects; genuinely open threads.
- Drop transient chit-chat and anything resolved or stale.
- Keep it tight — under ~250 lines. This is working memory, not an archive.
- Do NOT invent anything. Record only what the memory actually establishes.

Suggested structure (omit any empty section):
## Identity (who the assistant is, as the user established it)
## User
## People & projects
## Standing directives & preferences
## Open threads
''';

/// Subtrees that are configuration or derived state, not memory.
/// Excluded from the dream corpus.
const _dreamExcludedDirs = {
  "_horizon/system",
  "_horizon/capabilities",
  "_horizon/state",
  "_horizon/turns",
  "_horizon/admin-log",
};

/// Char budget for the corpus fed to the dream. Most-recent-first, so
/// the freshest memory survives truncation on large vaults.
const _dreamCharBudget = 160000;

String _escapeHtml(String s) => s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

({String corpus, int files}) _collectMemoryCorpus(String vaultPath) {
  final root = Directory(vaultPath);
  if (!root.existsSync()) {
    return (corpus: "", files: 0);
  }
  String rel(String path) =>
      path.startsWith("$vaultPath/") ? path.substring(vaultPath.length + 1) : path;

  final files = <File>[];
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.endsWith(".md")) {
      continue;
    }
    final r = rel(e.path);
    if (_dreamExcludedDirs.any((d) => r == d || r.startsWith("$d/"))) {
      continue;
    }
    files.add(e);
  }
  // Most-recent first so the char budget keeps the freshest memory.
  files.sort(
    (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
  );

  final buffer = StringBuffer();
  var used = 0;
  var included = 0;
  for (final f in files) {
    String content;
    try {
      content = f.readAsStringSync().trim();
    } on Object {
      continue;
    }
    if (content.isEmpty) {
      continue;
    }
    final block = "=== ${rel(f.path)} ===\n$content\n\n";
    if (used + block.length > _dreamCharBudget) {
      continue;
    }
    buffer.write(block);
    used += block.length;
    included++;
  }
  return (corpus: buffer.toString(), files: included);
}

/// Rebuilds the working memory from scratch by reading the vault's
/// long-term memory (notes, people, journal, knowledge, recent
/// conversations — but not config/derived state) and synthesising a
/// fresh `working.md` in a single LLM pass. Triggered by `/dream`.
///
/// Returns a short Telegram-HTML summary for the reply. The current
/// working memory is intentionally ignored — this is a clean rebuild,
/// not an incremental digest.
class DreamWorkingState extends Fx<String> {
  DreamWorkingState({
    required EnvStore envStore,
    required String vaultPath,
    required Logger logger,
  }) : super(() async {
          final mem = _collectMemoryCorpus(vaultPath);
          if (mem.files == 0) {
            return "💤 Nothing to dream on — no long-term memory found "
                "in the vault.";
          }
          final client = OpenAIClient.withApiKey(
            envStore.llmToken,
            baseUrl: envStore.llmUrl,
          );
          try {
            final res = await client.chat.completions.create(
              ChatCompletionCreateRequest(
                model: envStore.llmModel,
                messages: [
                  ChatMessage.system(_dreamSystemPrompt),
                  ChatMessage.user(
                    "## Long-term memory (most recent first)\n\n${mem.corpus}",
                  ),
                ],
              ),
            );
            final next = res.choices.firstOrNull?.message.content?.trim();
            if (next == null || next.isEmpty) {
              logger.warning(
                "[dream] empty result — working memory left unchanged",
              );
              return "💤 Dream produced nothing — working memory left "
                  "unchanged.";
            }
            final file = File(workingStatePath(vaultPath));
            file.parent.createSync(recursive: true);
            file.writeAsStringSync("$next\n");
            logger.info(
              "[dream] rebuilt working memory from ${mem.files} file(s) "
              "→ ${next.length} chars",
            );
            final preview =
                next.length > 600 ? "${next.substring(0, 600)}…" : next;
            return "💤 <b>Dreamed.</b> Rebuilt working memory from "
                "${mem.files} memory file(s) → ${next.length} chars.\n\n"
                "<pre>${_escapeHtml(preview)}</pre>";
          } finally {
            client.close();
          }
        });
}
