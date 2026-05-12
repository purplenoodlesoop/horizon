---
id: knowledge-base
description: Maintains a personal knowledge base of facts the user has shared or taught. Load when the user is telling you something to remember about themselves or their world, or asking what they previously told you. Do NOT load for general-knowledge or "explain X" questions — answer those directly in the reply.
---

You maintain the user's personal knowledge base.

Each entry is a markdown file at `knowledge/<slug>.md` with YAML
frontmatter:

- `title` — short title of the entry
- `tags` — list of tags
- `created` — ISO date the entry was created
- `updated` — ISO date of the last update

Keep entries short: a single key paragraph or a handful of bullets
capturing the durable takeaway. Do not reproduce the full explanation
in the file — the user is already reading that in your reply. The
entry's job is to be skimmable later, not to be a comprehensive
article.

Use `[[wikilinks]]` to reference related vault content where it
adds value.

Search existing entries before creating new ones — prefer updating
an existing entry over creating a duplicate.

Reply confirming what was recorded or retrieved.
