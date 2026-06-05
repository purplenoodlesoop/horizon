---
id: skill-reflector
description: Proposes new capabilities based on repeated patterns in recent activity. Load when the user asks to reflect, propose new skills, or look for patterns. To run it periodically add a real schedule: field (e.g. schedule: 7d); it never fires on an unscheduled heartbeat, so do not rely on a heartbeat trigger the harness cannot honor.
---

You propose new capabilities based on repeated patterns in recent
activity, following the Hermes-style skill memory pattern.

When invoked:

1. List `_horizon/messages/` and read the most recent entries — last
   7 days unless the user specifies otherwise. Each message file has
   a `## In` section (the raw user input) and a `## Out` section
   (what was done). The messages namespace is system-managed and
   always present; do not assume any other subtree exists.

2. Cluster repeated user requests by intent. A pattern is a sequence
   of three or more requests of the same kind handled the same way.
   Examples:
   - "log 30 minute walk", "log 1 hour cycle", "log yoga session" →
     pattern: exercise logging
   - "remember to call X", "remember to email Y", "remember the
     meeting at noon" → pattern: structured reminders

3. For each clear pattern, draft a new capability with:
   - A unique `id` (kebab-case, e.g., `exercise-tracker`)
   - A `description` that includes "Load when..." with concrete
     trigger phrases drawn from the observed requests
   - A short prose body describing the conventions: where to write
     files, what frontmatter to use, how to cross-reference

4. Write each draft to
   `_horizon/capabilities/proposed/<id>.md`. **Never** write to
   `_horizon/capabilities/<id>.md` directly. **Never** overwrite an
   existing proposal — if a proposal with that id already exists,
   choose a different id (e.g., `exercise-tracker-v2`) or skip.

5. Reply with a list of proposed capabilities, where each proposal
   lives, and one sentence on why the user might want to promote it
   (or reject it). The user promotes accepted proposals manually
   with `mv`. The reflector itself never gains promotion authority.

If no clear patterns are found, say so and reply with a single line.
Do not propose speculative capabilities for one-off requests.
