import "dart:async";
import "dart:io";

import "package:fn/fn.dart";
import "package:horizon/src/config/env_store.dart";
import "package:mark/mark.dart";
import "package:openai_dart/openai_dart.dart";

const _stateSubdir = "_horizon/state";
const _stateFile = "working.md";

String workingStatePath(String vaultPath) =>
    "$vaultPath/$_stateSubdir/$_stateFile";

/// Reads the consolidated working-memory notes for this vault.
///
/// This document is the product of an explicit, user-invoked `/dream`
/// consolidation — NOT a silent per-turn LLM rewrite (that mechanism was
/// removed in 0.2.0, #36, because it fabricated/dropped facts and
/// laundered the model's own inventions into authoritative memory). It is
/// injected each turn as BACKGROUND notes (see `centralized.dart`), not as
/// inviolable authority: the assistant starts from a useful summary but
/// reconstructs the present truth from the live vault and the user's
/// current words. Returns "" on cold start (no file).
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

const _dreamSystemPrompt = '''
You are the dreaming process for a personal assistant — the deep,
from-scratch memory consolidation that runs ONLY when the user asks for
it (`/dream`).

You are given the assistant's long-term memory: its notes, people files,
journal, knowledge base, and recent conversations. From ALL of it,
SYNTHESISE — from scratch — a single "working memory" document of
BACKGROUND NOTES the assistant starts each turn from. It is not the
source of truth (the vault files and the user are); it is an orientation
summary.

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
- Do NOT invent anything. Record only what the memory actually establishes;
  attribute identity/preferences only where the USER actually established
  them — never promote your own phrasing into a user-stated fact.
''';

/// Subtrees that are configuration or derived state, not memory.
/// Excluded from the dream corpus.
const _dreamExcludedDirs = {
  "_horizon/system",
  "_horizon/capabilities",
  "_horizon/state",
  "_horizon/turns",
  "_horizon/admin-log",
  "_horizon/schedules",
};

/// Basenames of the DERIVED working-memory store (and model-authored
/// look-alikes of it). Never fed back into a rebuild: re-ingesting a
/// stale or fabricated memory snapshot is the `/dream` re-poison route
/// (#37) — e.g. a `working-memory.md` the model once wrote by hand at the
/// vault root, outside the excluded `_horizon/state` subtree.
const _memoryStoreBasenames = {"working.md", "working-memory.md"};

/// Wall-clock cap on the dream LLM call so a hung provider can't leave
/// `/dream` spinning forever (#33).
const _dreamTimeout = Duration(seconds: 120);

/// Char budget for the corpus fed to the dream. Most-recent-first, so
/// the freshest memory survives truncation on large vaults.
const _dreamCharBudget = 160000;

String _escapeHtml(String s) => s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;");

/// Boundary-aware preview for the `/dream` confirmation: cut on a line
/// boundary (never mid-token) and label it, instead of a blind 600-char
/// substring that lands inside an arbitrary sentence (#37).
String _dreamPreview(String s, int max) {
  if (s.length <= max) {
    return s;
  }
  var cut = s.lastIndexOf("\n", max);
  if (cut < max ~/ 2) {
    cut = max;
  }
  return "${s.substring(0, cut).trimRight()}\n"
      "… (preview — full memory in _horizon/state/working.md)";
}

({String corpus, int files}) _collectMemoryCorpus(String vaultPath) {
  final root = Directory(vaultPath);
  if (!root.existsSync()) {
    return (corpus: "", files: 0);
  }
  String rel(String path) => path.startsWith("$vaultPath/")
      ? path.substring(vaultPath.length + 1)
      : path;

  final files = <File>[];
  for (final e in root.listSync(recursive: true, followLinks: false)) {
    if (e is! File || !e.path.endsWith(".md")) {
      continue;
    }
    final r = rel(e.path);
    if (_dreamExcludedDirs.any((d) => r == d || r.startsWith("$d/"))) {
      continue;
    }
    if (_memoryStoreBasenames.contains(r.split("/").last)) {
      // #37: never re-ingest the derived working-memory store or a
      // model-authored look-alike — that is the re-poison route.
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

/// Rebuilds the working-memory notes from scratch by reading the vault's
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
            final res = await client.chat.completions
                .create(
                  ChatCompletionCreateRequest(
                    model: envStore.llmModel,
                    messages: [
                      ChatMessage.system(_dreamSystemPrompt),
                      ChatMessage.user(
                        "## Long-term memory (most recent first)\n\n"
                        "${mem.corpus}",
                      ),
                    ],
                  ),
                )
                .timeout(_dreamTimeout);
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
            final preview = _dreamPreview(next, 600);
            return "💤 <b>Dreamed.</b> Rebuilt working memory from "
                "${mem.files} memory file(s) → ${next.length} chars.\n\n"
                "<pre>${_escapeHtml(preview)}</pre>";
          } on TimeoutException {
            logger.warning(
              "[dream] timed out after ${_dreamTimeout.inSeconds}s — "
              "working memory left unchanged",
            );
            return "💤 Dream timed out — working memory left unchanged.";
          } finally {
            client.close();
          }
        });
}
