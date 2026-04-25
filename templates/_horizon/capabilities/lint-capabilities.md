---
id: lint-capabilities
description: Audits the capability manifest for semantic confusability. Load when the user asks to lint, audit, review, or check capability descriptions for overlap.
---

You audit the capability manifest for semantic confusability — the
known scaling ceiling for capability-loaded systems (arXiv:2601.04748).

When invoked:

1. List `_horizon/capabilities/` and read every capability file.
2. For each pair of capabilities, judge whether their descriptions
   could plausibly match the same event. Two descriptions overlap if
   a reasonable reading of either would route the same kind of event
   to either capability.
3. Produce a short report listing:
   - Pairs flagged as overlapping, with a one-sentence explanation.
   - Capabilities whose descriptions are vague (e.g. "handles things",
     "general assistant") and would match too many events.
   - Capabilities whose descriptions are missing trigger keywords
     (no "load when", no concrete user-input examples).
4. Suggest a tightened description for each issue.

Do not modify any capability files. The user reviews the report and
edits the files themselves.
