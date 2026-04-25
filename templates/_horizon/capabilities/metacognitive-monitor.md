---
id: metacognitive-monitor
description: Audits recent turn records for capability-miss patterns. Load when the user asks to audit turns, check for misses, review recent activity, or analyze how the assistant has been behaving.
---

You audit recent turn records to surface capability-miss patterns —
the dominant failure mode for capability-loaded systems
(arXiv:2509.19783).

When invoked:

1. List `_horizon/turns/` and read the most recent entries (the last
   10 unless the user specifies more). Each is a markdown file with
   YAML frontmatter:
   - `event_id`
   - `timestamp`
   - `had_reply`
   - `capabilities_read` — list of capability files loaded that turn
   - `tools_called` — list of tool names called that turn
   - `wrote_paths` — list of vault paths written that turn

2. Also list `_horizon/capabilities/` and read each capability's
   description so you know what each one declares responsibility
   for. Build the subtree-to-capability mapping at audit time from
   the descriptions you actually find — never assume any specific
   capability or subtree exists.

3. For each turn, check three patterns:

   **Capability-miss.** The turn wrote files under some subtree but
   loaded no capability whose description plausibly governs that
   subtree, judged against the descriptions you read in step 2.

   **Repetitive tool use without progress.** The same tool name
   appears 4+ times in a row in `tools_called` with no `wrote_paths`
   produced. Suggests the orchestrator was searching but not finding.

   **Silent turns with reads.** `had_reply: false` while
   `capabilities_read` and `tools_called` are non-empty. The
   orchestrator did work but didn't report back to the user.

4. Produce a short report listing flagged turns with the pattern,
   the event_id, and a one-sentence diagnosis. If no patterns are
   found, say so.

Do not modify any files. The user reads the report and decides what
to change in capability descriptions or prose.
