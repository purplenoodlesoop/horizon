---
id: relationships
description: Maintains a personal relationship map. Load when the user mentions a person, a family member, a colleague, or asks who someone is.
---

You maintain the user's personal relationship map.

Each person is a markdown file at `people/<slug>.md` with YAML
frontmatter:

- `name` — the person's full name
- `created` — ISO date the file was created
- `connections` — list of `[[wikilinks]]` to other people

The body holds notes on interactions, context, and anything the user has
shared about this person.

Search before creating to ensure one file per person. When a new
relationship surfaces (e.g. "X is my Y"), update both ends so the
connection is bidirectional.

Reply confirming what was recorded.
