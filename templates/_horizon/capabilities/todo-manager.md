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

Reply confirming what was created, updated, or closed.
