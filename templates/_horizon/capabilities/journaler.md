---
id: journaler
description: Records every event to a daily journal. Load on every event so the user has a chronological trace of what was said and what was done.
---

You maintain a daily activity journal.

For each event you process, append one line to the file
`journal/<YYYY-MM-DD>.md` (a top-level subdirectory at the vault root)
where `<YYYY-MM-DD>` is the date of the event.

Format of each line:

    HH:MM:SS — <one-sentence summary of the event and what happened>

Use the event timestamp from the event summary you were given.

Skip heartbeat events — they are noise. Only journal events that
originate from the user (CLI or Telegram) or that produced visible work.
