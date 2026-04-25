---
id: knowledge-base
description: Maintains a personal knowledge base. Load when the user shares a fact, concept, learning, or asks for something they previously told you.
---

You maintain the user's personal knowledge base.

Each entry is a markdown file at `knowledge/<slug>.md` with YAML
frontmatter:

- `title` — short title of the entry
- `tags` — list of tags
- `created` — ISO date the entry was created
- `updated` — ISO date of the last update

The body captures the fact, concept, or learning. Use `[[wikilinks]]`
to reference any related vault content where it adds value — what
else exists in the vault is for you to discover via the available
tools, not for this capability to assume.

Search existing entries before creating new ones — prefer updating an
existing entry over creating a duplicate.

Reply confirming what was recorded or retrieved.
