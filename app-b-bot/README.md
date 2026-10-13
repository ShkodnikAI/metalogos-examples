# App B — the bot on mlogpkg

**Owner:** naryad №681 (P1, examples) — [Metalogos- gh#1232](https://github.com/ShkodnikAI/Metalogos-/issues/1232), Wave 42.
**Charter:** [ADR-0190 §2.2](https://github.com/ShkodnikAI/Metalogos-/blob/main/docs/adr/0190-examples-showcase.md) — a chat-bot skeleton: poll/hook intake + a dialog state machine + one outbound client call behind a deterministic stub.

## What this app demonstrates

The directory IS an mlogpkg package (`mlog.toml`, the entry point at
`src/main.mlog`, zero dependencies — offline). The bot skeleton has three
moves:

1. **INTAKE — two modes over the same handler:**
   - **HOOK:** `POST /hook {chat, text}` — the webhook-style update,
     processed immediately;
   - **POLL:** `POST /enqueue {chat, text}` queues the update, and
     `POST /poll` drains it one update per call — the poll-loop
     iteration, driven manually. The external world is REPLACED by the
     queue (the deterministic stand-in: no network, no scheduler timing
     in the showcase).
2. **DIALOG STATE MACHINE** — the per-chat dialog state lives in the
   typed-memory registry (the process-global, backend-independent
   surface, №520): `new → greeted → helped`, per chat id; unknown chats
   start fresh.
3. **OUTBOUND** — `send_message(chat, reply)`. Without
   `TELEGRAM_BOT_TOKEN` the call is the deterministic `[AUDIT]` stub
   (stderr) — the external API client call closed behind the stub,
   offline. The route responses carry the full `state=... -> reply`
   transitions, so the transcript is fully deterministic.

## The honest boundaries

- **The mlogpkg surface vs the pinned release assets.** The pinned core
  release carries only `mlog-linux-x86_64` — the `mlogpkg` BINARY is not
  among the release assets, so the e2e exercises exactly the surface the
  pin carries: the manifest shape is validated, and the source is
  semantic-checked via `mlog check` — the same `check_program` family
  `mlogpkg build` runs. When a future release ships the mlogpkg binary,
  bumping the pin (a small PR with the both-backend proof) extends this
  leg to a real `mlogpkg build`.
- **The scheduler is NOT in the bot.** The cron/poll timing legs live in
  the core's own serve-e2e (№522); the showcase stays bounded and
  deterministic — the poll intake is the queue-drain shape, driven
  manually.
- **The middleware advisories are left open on purpose.** `mlog check`
  recommends `security_headers`/`csrf` middlewares for browser-facing
  surfaces; this bot is a machine-to-machine API demo (no browser forms,
  no CSRF context) — the advisories are noted, not silenced.
- The state machine never branches on a read VALUE — only on the
  try-object's success flag and the bot's own state constants — the
  Category A `UNTRUSTED_DECISION` gate stays quiet for the right reason.

## How to run

```bash
# from the repository root — the pinned core is fetched and verified first
bash e2e/run_all.sh
```

The e2e leg (`e2e/app_b.sh`) validates the manifest, semantic-checks the
source, then boots the bot on BOTH backends
(`METALOGOS_SERVE_BACKEND=interpreter` then `=vm`), scripts the dialog
(hook arc + poll arc) per backend, and diffs the transcripts
(`assert_identical`, §2.4).

## The parity proof (recorded)

Both transcripts from a green local run of the pinned core v0.30.1
(27877b8) — identical, TW == VM:

```
hook u1 start: state=new -> welcome to the showcase bot
hook u1 help:  state=greeted -> commands: start, help, anything-else echoes back
hook u1 ping:  state=helped -> echo: ping
hook u2 hi:    state=new -> welcome to the showcase bot
enqueue u3 start: queued:0
enqueue u3 help:  queued:1
poll 1: poll: state=new -> welcome to the showcase bot
poll 2: poll: state=greeted -> commands: start, help, anything-else echoes back
poll 3: poll: queue empty
audit-stub: present (7 sends)
```

The `u2` chat starts fresh while `u1` is deep in its dialog — the state
machine is per-chat; the poll intake runs the SAME handler over the
queued updates; the outbound went through the deterministic stub (7
sends: 1 readiness probe + 4 hook + 2 poll). The CI re-proves the
both-backend parity on every PR and every push to main.

## Boundaries (continued)

- Offline-only (ADR-0190 §2.2): no live providers, no network; the stub
  is part of the showcase, not part of the core.
- No keys/secrets in the repository; `TELEGRAM_BOT_TOKEN` is explicitly
  empty in the e2e.
- The showcase is NOT a GFI (№561) and adds no language constructs (§4).
