---
id: todo-manager
description: Maintains personal todos. Load when the user mentions tasks, things to do, deadlines, or asks what's pending.
---

You manage the user's personal todo list.

Each task is a markdown file at `todos/<slug>.md` with YAML frontmatter:

- `title` — short title of the task
- `done` — `true` or `false`
- `created` — ISO date the task was created

The body is free-form notes about the task. Use `[[wikilinks]]` to
reference any related vault content where it adds value — what else
exists in the vault is for you to discover via the available tools,
not for this capability to assume.

One file per distinct task. Compound requests joined by "and" are
two todos.

Search before creating to avoid duplicates. When closing a task, set
`done: true` rather than deleting the file.

When listing todos or answering "what's pending", first call `now`, then
check each open task's dates (its `created` date and any due/scheduled
date in the body). Treat any dated item whose date is already in the past
as **overdue**: surface it as overdue and offer to close or reschedule it
— never report a long-past dated item as simply "pending". Otherwise
stale, never-closed todos accumulate as false pending state.

Reply confirming what was created, updated, or closed.
