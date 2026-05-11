# Horizon

A personal multi-agent assistant. Vault-resident capabilities, single-thread centralized orchestration, signal-driven heartbeat, Obsidian as state, Telegram + CLI as channels, Kimi K2.6 on CrofAI as the default LLM (any OpenAI-compatible provider works). One user, one vault, one binary.

This README is the only source of documentation.

## Table of contents

- [What Horizon is](#what-horizon-is)
- [Quick start (nix, no installation)](#quick-start-nix-no-installation)
- [Quick start (dart, local clone)](#quick-start-dart-local-clone)
- [Configuration](#configuration)
- [The vault](#the-vault)
- [Capabilities](#capabilities)
  - [Format](#format)
  - [Authoring rules](#authoring-rules)
  - [Default bundle](#default-bundle)
- [Orchestration](#orchestration)
- [Heartbeat (signal-driven)](#heartbeat-signal-driven)
- [Tools](#tools)
  - [Vault I/O](#vault-io)
  - [System](#system)
  - [Web](#web)
  - [Outbound](#outbound)
  - [Adding a tool](#adding-a-tool)
- [Channels](#channels)
  - [CLI](#cli)
  - [Telegram (username allowlist)](#telegram-username-allowlist)
- [Security model](#security-model)
- [System prompt tuning](#system-prompt-tuning)
- [Cost characteristics](#cost-characteristics)
- [What Horizon will never be](#what-horizon-will-never-be)
- [Project layout](#project-layout)
- [Development](#development)

---

## What Horizon is

A single-user personal assistant that lives in your Obsidian vault. You add a capability — a markdown file describing what kind of work it handles — and the orchestrator pulls it into context when relevant. The vault is the only persistent state; the harness is generic and knows nothing about people, todos, journals, or any other subtree.

Three properties make this different from the other personal-assistant frameworks:

1. **Vault-resident behavior.** Capabilities live as markdown files inside the vault, alongside your notes. Edit a capability in Obsidian and the next event uses the new behavior — no restart.
2. **Signal-driven proactivity.** The heartbeat does nothing by default. Capabilities can declare a `schedule:` field; the harness fires the LLM only when at least one capability is due. Empty ticks cost zero tokens.
3. **Bash allowlist as the tool primitive.** New tools are YAML edits in `<vault>/_horizon/system/allowlist.yaml` — vault-resident, hot-reloaded on every event, editable from Obsidian Mobile. No MCP, no per-tool Dart code, no server lifecycle. Curl, jq, and the file system are the toolkit.

---

## Quick start (nix, no installation)

```sh
# .env in your current directory must contain at least
#   TELEGRAM_TOKEN=<bot token>
#   TELEGRAM_USERNAME=<your-telegram-username>
#   LLM_TOKEN=<crof.ai key — default backend>
#   TAVILY_TOKEN=<tavily key, optional, enables web_search>
# Optional, to swap LLM provider (defaults: CrofAI + kimi-k2.6):
#   LLM_URL=https://api.fireworks.ai/inference/v1
#   LLM_MODEL=accounts/fireworks/models/kimi-k2p5

nix run github:purplenoodlesoop/horizon
```

The flake bundles the templates (capabilities, system prompts, default tool allowlist) into the package, so the binary works from any directory. On first run, an empty vault is bootstrapped with the default capability set and `_horizon/system/allowlist.yaml`. After that, you edit tools and capabilities in Obsidian and the next event picks up the changes — no restart, no redeploy.

---

## Configuration

| Flag | Env var | Default | Required | Notes |
|---|---|---|---|---|
| `--telegram-token` | `TELEGRAM_TOKEN` | — | yes | Bot token from @BotFather |
| `--telegram-username` | `TELEGRAM_USERNAME` | — | **required for any inbound traffic** | Telegram username(s) the bot accepts messages from. Without `@`. Single value for original single-user mode, or comma/space-separated list for multi-user (`alice,bob`). Empty = fail-closed (all inbound dropped, startup warns) |
| `--llm-token` | `LLM_TOKEN` | — | yes | API key for the LLM provider (default backend is CrofAI) |
| `--llm-url` | `LLM_URL` | `https://crof.ai/v1` | no | Base URL of an OpenAI-compatible chat completions endpoint (no trailing `/chat/completions`). Other options: `https://api.fireworks.ai/inference/v1`, `https://openrouter.ai/api/v1` |
| `--llm-model` | `LLM_MODEL` | `kimi-k2.6` | no | Model id the provider expects. On Fireworks use `accounts/fireworks/models/kimi-k2p5`; on CrofAI also try `kimi-k2.6-precision` or `kimi-k2.5` |
| `--tavily-token` | `TAVILY_TOKEN` | — | optional | Enables `web_search`. Without it, the tool fails when called |
| `--vault` | — | `vault` | no | Path to the Obsidian vault |
| `--allowlist` | `HORIZON_ALLOWLIST` | `<vault>/_horizon/system/allowlist.yaml` | no | Tool definitions YAML; override only — the harness reads from the vault by default and reloads per event |
| `--templates` | `HORIZON_TEMPLATES` | `templates` | no | Bootstrap source for `_horizon/` |
| `--heartbeat` | — | `300` | no | Heartbeat interval in seconds |
| `--mode` | — | `human` | no | `human` for interactive, `agent` for JSON output |
| `--env-file` | — | `.env` | no | KEY=VALUE file loaded before flag/env resolution |

The Nix package sets `HORIZON_TEMPLATES` to the install-prefix path via a wrapper, so `nix run` works from any directory. The first run bootstraps `_horizon/system/allowlist.yaml` from that template into your vault; subsequent edits live in the vault.

---

## The vault

The vault is plain markdown with YAML frontmatter and `[[wikilinks]]`. Open it in Obsidian; everything is human-readable.

The harness reserves one subtree, `<vault>/_horizon/`, for system-managed state:

```
<vault>/
├── _horizon/
│   ├── capabilities/        # capability prose, edit freely
│   │   ├── todo-manager.md
│   │   ├── relationships.md
│   │   ├── knowledge-base.md
│   │   ├── journaler.md
│   │   ├── lint-capabilities.md
│   │   ├── metacognitive-monitor.md
│   │   └── skill-reflector.md
│   ├── system/              # system prompt templates, edit to tune
│   │   ├── standing.md
│   │   └── heartbeat-addendum.md
│   ├── messages/            # one file per inbound channel event + reply
│   ├── turns/               # structured per-turn record (capabilities loaded, tools called, paths written)
│   └── (capabilities/proposed/, written by the skill-reflector)
└── (everything else is yours — todos/, people/, journal/, knowledge/, anything)
```

The harness writes to `_horizon/messages/`, `_horizon/turns/`, and on first run copies `templates/_horizon/` into `<vault>/_horizon/`. Capabilities decide where else to write; the harness has no opinions about user-content layout.

---

## Capabilities

A capability is a markdown file at `<vault>/_horizon/capabilities/<id>.md`. It is the only abstraction Horizon has for "what the assistant can do" — they replace the older notion of agents entirely.

### Format

```markdown
---
id: todo-manager
description: Maintains personal todos. Load when the user mentions tasks, things to do, deadlines, or asks what's pending.
schedule: 1d              # optional — eligible to fire on heartbeat
---

You manage the user's personal todo list.

Each task is a markdown file at `todos/<slug>.md` with YAML frontmatter:

- `title` — short title of the task
- `done` — `true` or `false`
- `created` — ISO date the task was created

The body is free-form notes about the task. Use `[[wikilinks]]` to
reference any related vault content where it adds value.

One file per distinct task. Compound requests like "do X and Y"
produce two separate todos, unless one is clearly a sub-step of the
other.

Reply confirming what was created, updated, or closed.
```

Frontmatter fields:

| Field | Required | Purpose |
|---|---|---|
| `id` | yes | Unique kebab-case identifier |
| `description` | yes | The manifest entry the orchestrator sees in its system prompt. Lead with "Load when…" so the model can decide whether to pull this body in |
| `schedule` | no | Duration string (`30m`, `1h`, `1d`, `7d`, `1w`). Capabilities with this field are eligible to fire on heartbeat |

The body is prose: role, conventions, file naming, anything the orchestrator should know once the capability is loaded.

### Authoring rules

The harness is generic. To keep capabilities portable across vaults with different conventions, follow these rules in capability prose:

1. **Each capability declares only its own subtree.** A `todo-manager` may say "todos live at `todos/<slug>.md`". It must not assume `people/` or `knowledge/` exist; the orchestrator will figure out cross-domain links at runtime when multiple capabilities are loaded.
2. **Path conventions go in the body, not the frontmatter.** No `write_path:` field. The body is human-readable prose, not machine-enforced policy.
3. **Lead the description with a "Load when…" clause.** The orchestrator routes by reading descriptions; vague descriptions cause routing misses.
4. **Capabilities never reference other capabilities by name.** Cross-coordination emerges at runtime.
5. **Don't write to `_horizon/`.** That's the system namespace. The exception is `_horizon/capabilities/proposed/`, which is the convention for the skill-reflector to drop new capability proposals.

### Default bundle

| Capability | Purpose |
|---|---|
| `todo-manager` | Personal todos under `todos/<slug>.md` |
| `relationships` | People under `people/<slug>.md` with bidirectional `connections` |
| `knowledge-base` | Facts and learnings under `knowledge/<slug>.md` |
| `journaler` | One-line entries appended to `journal/<YYYY-MM-DD>.md` per event |
| `lint-capabilities` | LLM-driven audit of capability descriptions for semantic confusability |
| `metacognitive-monitor` | LLM-driven audit of recent turn records for capability-miss patterns |
| `skill-reflector` | Proposes new capabilities into `_horizon/capabilities/proposed/` based on repeated patterns. **Ships without `schedule:`** — opt in by adding e.g. `schedule: 7d` to the frontmatter |

Defaults are a starting point. Wipe `<vault>/_horizon/capabilities/` and write your own — the harness will not reseed unless `_horizon/` is missing entirely.

---

## Orchestration

One LLM call per event. The system prompt looks like:

```
[standing prose from <vault>/_horizon/system/standing.md]

Available capabilities — markdown files describing how to handle ...:
- todo-manager (_horizon/capabilities/todo-manager.md): Maintains personal todos. Load when the user mentions...
- relationships (_horizon/capabilities/relationships.md): Maintains a personal relationship map. Load when...
- ...

[standing instructions about wikilinks, plain text replies, etc.]
```

The user message contains the per-event volatile content (event summary + raw input). Everything in the system prompt is byte-identical across events for a given vault, so providers that do prefix/KV caching (Fireworks, OpenAI, Anthropic, etc.) hit the prefix at ~70–85% on second-and-later turns. Providers without prefix caching will re-prefill on every turn — the cost section below assumes a cache-supporting backend.

The orchestrator uses `read_file` to pull capability bodies on demand. Loading a capability and acting on it are the same model call — there is no separate routing step. This is the key architectural choice; it sidesteps the misclassification ceiling of cheap-router approaches.

---

## Heartbeat (signal-driven)

The harness emits a heartbeat event on `--heartbeat` interval. Heartbeat dispatch is signal-driven:

1. **Pre-LLM filter** (pure Dart, no token cost). The harness lists capabilities whose frontmatter declares a `schedule:` field, then reads `_horizon/turns/` to find each capability's last firing. A capability is *due* if it has never fired or if `now - last_fire >= schedule`.
2. **Skip on empty.** If no capabilities are due, the harness returns without invoking the LLM. Heartbeats with nothing due cost zero LLM tokens.
3. **Stripped manifest on fire.** When at least one capability is due, the orchestrator gets a manifest containing only those due capabilities and an instruction to reply with the sentinel `HEARTBEAT_OK` if it finds nothing actionable. The harness suppresses that sentinel before delivery.

To enable a proactive capability, add `schedule:` to its frontmatter:

```markdown
---
id: skill-reflector
description: Proposes new capabilities based on repeated patterns…
schedule: 7d
---
```

Default capabilities ship without `schedule:` — proactive behavior is opt-in.

---

## Tools

Tools are bash command templates in `<vault>/_horizon/system/allowlist.yaml`. The harness renders a template with shell-escaped arguments, validates, runs through `bash -c`, and returns stdout/stderr to the orchestrator. The file is read on every event, so edits in Obsidian Mobile take effect on the next message — no restart needed. The bundled default allowlist is shipped in `templates/_horizon/system/allowlist.yaml` and copied into your vault on first run.

### Vault I/O

| Tool | Purpose |
|---|---|
| `read_file(path)` | `cat <vault>/<path>` |
| `write_file(path, content)` | `printf '%s' <content> > <vault>/<path>` (auto-mkdir) |
| `list_files()` | `find <vault> -name '*.md' -type f` |
| `list_files_glob(pattern)` | `find <vault> -type f -name <pattern>` (covers non-`.md`) |
| `search_vault(query)` | `grep -rliE <query> <vault> --include='*.md'` |
| `delete_file(path)` | `rm -f <vault>/<path>` |

### System

| Tool | Purpose |
|---|---|
| `now()` | `date -u +%Y-%m-%dT%H:%M:%SZ` |

### Web

| Tool | Purpose |
|---|---|
| `fetch_url(url)` | Raw curl GET |
| `fetch_url_text(url)` | Page rendered to readable markdown via Jina Reader (`r.jina.ai`), no key needed |
| `web_search(query)` | Tavily search; returns top-5 results as JSON. Requires `TAVILY_TOKEN` |

### Outbound

| Tool | Purpose |
|---|---|
| `send_telegram(chat_id, text)` | POSTs `sendMessage` to Telegram. The `chat_id` parameter is type `telegram_chat_id` — the harness rejects any value that hasn't sent the bot an accepted message (i.e. doesn't appear in `_horizon/messages/`). Outbound is bounded by inbound |

### Adding a tool

Append to `<vault>/_horizon/system/allowlist.yaml` (in Obsidian or via your editor of choice):

```yaml
  - name: weather
    description: Get the current weather for a location.
    parameters:
      location:
        type: string
        description: City name or "lat,lon"
    command: "curl -sS 'https://wttr.in/'{location}'?format=3'"
```

No restart needed — the next event picks up the new tool. Secret credentials (API keys) should be passed via env vars (added to `executor.dart`'s `Process.run` env, hot-reloaded from `.env`) and referenced as `$VAR_NAME` in the template — never substituted via `{var}`, since substitution puts them in the rendered command string.

Custom param types currently recognized:

- `path` — validated to stay under the vault root (no `..` traversal)
- `telegram_chat_id` — validated to appear in `_horizon/messages/` frontmatter

---

## Channels

### CLI

`dart run bin/horizon.dart` reads stdin line-by-line. Each non-empty line becomes an event. Replies print to stdout in `human` mode, JSON in `agent` mode. Useful for piping scripts and for use under Claude Code.

### Telegram (username allowlist)

The Telegram bot accepts inbound only from an explicit username allowlist. Set `TELEGRAM_USERNAME=<your_username>` for a single user, or a comma/space-separated list (`TELEGRAM_USERNAME=alice,bob`) for multi-user. All entries are stripped of an optional leading `@` and compared case-insensitively. The harness enforces:

- **Inbound**: `TelegramPoller` drops every update where `message.from.username` is not in the allowlist. Other users' messages are silently discarded.
- **Outbound**: the `send_telegram` tool's `chat_id` parameter has type `telegram_chat_id`. The executor rejects any chat_id that has not previously sent the bot an accepted message. The set of allowed chat_ids is derived live from `_horizon/messages/` frontmatter.
- **Same-chat duplicate guard**: when the orchestrator is currently replying inside a Telegram chat, calling `send_telegram` with that same `chat_id` is refused with an error (the final assistant message already lands in that chat — calling `send_telegram` would produce a duplicate).
- **Inline / guest mode**: non-allowlisted users who invoke the bot inline (`@yourbot foo`) get a single canned result instructing them to message the owner. Inline queries from allowlisted users return an empty result for now (the inline answer surface is a v1 placeholder).

Net effect: each allowed user must DM the bot at least once to "register" their chat_id; afterward, capabilities can push proactively to that chat. The bot will never accept or send outside the registered allowlist.

If `TELEGRAM_USERNAME` is empty, the harness logs a startup warning and **drops every inbound message** (fail-closed). An unset username is treated as a misconfiguration, never as "allow everyone."

---

## Security model

- **Tool allowlist.** Only commands declared in `<vault>/_horizon/system/allowlist.yaml` execute. Unknown tool names return an error before bash sees anything. The vault is single-user-write by virtue of the device sync model (your Obsidian vault, your phone), so vault-resident allowlist edits sit inside the same trust boundary as capability prose.
- **Path traversal.** `path`-typed parameters are checked to stay under `<vault>/`; any `..` or absolute path is refused.
- **Shell escaping.** Every parameter value is wrapped in single quotes with embedded single quotes escaped. The orchestrator cannot inject shell metacharacters by crafting a parameter.
- **No pipe-to-interpreter.** Rendered commands are scanned for `| sh`, `| bash`, `| python`, etc., and refused at validation time.
- **Secret tokens via env.** `TELEGRAM_TOKEN` and `TAVILY_TOKEN` are passed to the bash subprocess as environment variables, never substituted into the rendered command. They do not appear in process listings, command logs, or tool-call debug output.
- **Single-user Telegram lockdown.** See above.
- **No adversarial threat model.** The orchestrator (the LLM) is trusted; this is your bot acting on your vault. Validation prevents the orchestrator from accidentally writing outside the vault or hallucinating destructive commands, not from an attacker.

---

## System prompt tuning

The standing prompt and the heartbeat addendum live as plain markdown:

- `<vault>/_horizon/system/standing.md` — base prompt, with `{{manifest}}` substituted at runtime
- `<vault>/_horizon/system/heartbeat-addendum.md` — appended in heartbeat mode

Edit them in Obsidian. The next event uses the new prompt. The harness reads from the vault first, falling back to `templates/_horizon/system/` if the vault copy is missing.

The only mechanical placeholder is `{{manifest}}`. Everything else is literal text.

---

## Cost characteristics

Empirical reference numbers, taken on Kimi K2.5 via Fireworks ($0.60/M input, $3.00/M output as of 2026-04) — the previously-default setup. The current default (CrofAI + `kimi-k2.6`) hasn't been benchmarked against these figures; treat them as an order-of-magnitude guide. Other providers via `LLM_URL`/`LLM_MODEL` will differ.

| Scenario | Per-event cost |
|---|---|
| Conversational message (5 turns of agentic loop, 4–8k tokens prompt with ~75% cache hit) | ~$0.01–0.03 |
| Empty heartbeat (no scheduled capability due) | $0 |
| Heartbeat with `skill-reflector` due (1 turn read journal/messages + write a proposal) | ~$0.05 |
| Web search via Tavily | ~$0.005 incremental for the Tavily call + LLM tokens |

The KV cache discipline matters: the system prompt prefix is byte-identical across events for a given vault, so a prefix-caching backend (Fireworks, OpenAI, etc.) caches it. The user message holds the volatile event summary so the prefix isn't disrupted. If you point `LLM_URL` at a provider that doesn't do prefix caching, expect the per-event prompt cost to multiply roughly 4×.

---

## What Horizon will never be

- Multi-user. The bot is locked to one Telegram username; outbound is bounded by inbound.
- Multi-vault. One process, one vault.
- Real-time (sub-second). Every event waits on a Kimi K2.5 round-trip.
- An MCP host or client. Bash command templates are the equivalent and operationally superior primitive at this scale; MCP adds a wire protocol, server lifecycle, and out-of-process orchestration with no functional gain.
- Self-modifying. The skill-reflector can *propose* new capabilities into `_horizon/capabilities/proposed/`; promotion is a manual `mv`.
- A framework. There is no plugin API, no extension point beyond YAML tool entries and markdown capabilities. The runtime is a single Dart binary.

---

## Project layout

```
horizon/
├── bin/horizon.dart              # entry point
├── lib/src/
│   ├── agent/
│   │   ├── pipeline.dart         # PipelineResult typedef + decay constant
│   │   ├── system_prompt.dart    # loads standing.md + addendum
│   │   └── pipelines/
│   │       └── centralized.dart  # the only pipeline
│   ├── capability/
│   │   ├── capability.dart       # type + LoadCapabilities
│   │   ├── lint.dart             # startup identical-description check
│   │   └── schedule.dart         # parseSchedule + DueCapabilities
│   ├── channel/
│   │   ├── cli.dart              # stdin → events; heartbeat factory
│   │   ├── reply.dart            # SendReply (Telegram or no-op for CLI)
│   │   └── telegram.dart         # polling + username allowlist
│   ├── config/
│   │   ├── args.dart             # ParseArgs
│   │   └── config.dart           # HorizonConfig
│   ├── event/event.dart          # Event + Channel sealed class
│   ├── harness/
│   │   ├── harness.dart          # event loop
│   │   ├── bootstrap.dart        # first-run template copy
│   │   ├── message_store.dart    # _horizon/messages/ persistence
│   │   ├── turn_store.dart       # _horizon/turns/ persistence
│   │   ├── console_logger.dart
│   │   └── file_logger.dart
│   ├── llm/client.dart           # OpenAI-compatible chat call + tool loop + usage logging
│   ├── tool/
│   │   ├── allowlist.dart        # YAML loader
│   │   ├── executor.dart         # render + validate + bash
│   │   └── security.dart         # path/command validation + chat_id allowlist
│   └── vault/summary.dart        # event summary formatter
├── templates/_horizon/           # bootstrap content (copied into the vault on first run)
│   ├── capabilities/             # default capability bundle
│   └── system/                   # standing prompt + heartbeat-addendum + default allowlist.yaml
├── flake.nix                     # Nix package + app
└── nix/horizon.nix               # derivation (dart compile + wrap)
```

---

## Development

```sh
# Local dev shell with dart available
direnv allow                       # if .envrc is set; else nix develop

# After changing any @freezed type
dart run build_runner build --delete-conflicting-outputs

# Static analysis
dart analyze

# Compile to a standalone binary
dart compile exe bin/horizon.dart -o /tmp/horizon-test

# Acceptance test (5-message protocol)
rm -rf /tmp/test-vault
printf 'I am Alex Smith\nMy mother is Maria Smith\nI need to create paypal for my mother and enable perplexity subscription\nI need to take a walk with my mother\nWhat todos do I have?\n' \
  | dart run bin/horizon.dart --vault=/tmp/test-vault --heartbeat=3600
```

The codebase is small (~1.6k lines of hand-written Dart).
