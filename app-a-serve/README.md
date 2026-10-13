# App A — the stateful serve application

**Owner:** naryad №680 (P1, examples) — [Metalogos- gh#1231](https://github.com/ShkodnikAI/Metalogos-/issues/1231), Wave 42.
**Charter:** [ADR-0190 §2.1](https://github.com/ShkodnikAI/Metalogos-/blob/main/docs/adr/0190-examples-showcase.md) — a small web service with state, retold as a USER story.

## What this app demonstrates

One `.mlog` program (`serve.mlog`, **62 lines — within the ≤120 budget**)
serves three routes over the typed-memory registry:

| Route | What it does |
|---|---|
| `POST /note` `{key, text}` | persists one note (`memory_open` + `memory_put`) |
| `POST /note/read` `{key}` | queries one note (`memory_read`); a missing key is the typed `MEMORY_UNKNOWN_KEY` refusal — the loud error response |
| `POST /notes` | lists the keys (`memory_keys`; the order is the container's hash-map order, so consumers check CONTAINS, not ordering) |

The state story is the restart arc: **persist → query → restart → query**.
The state survives a server RESTART through the persistence anchors
(`METALOGOS_MEMORY_DB` + `METALOGOS_MEMORY_MASTER`) — a fresh process
re-opens and decrypts the store (the load-on-open posture, №351 /
ADR-0173 §3.5).

## The honest subset (ADR-0190 §2.4)

The app rides the **typed-memory arc** (`memory_open` / `memory_put` /
`memory_read` / `memory_keys` — the process-global, backend-independent
registry, naryad №520). The simple `memory { persist }` +
`memorize`/`recall` lane is **request-scoped on the VM BY DESIGN** (the
№442 isolation pin), so it is deliberately NOT part of the cross-request
state story here. Widening the subset is a small PR with the
both-backend proof.

One security idiom worth copying: the routes never branch on a read
value — a decision on untrusted data is a Category A violation
(`UNTRUSTED_DECISION`). The persistence assertions live in the e2e leg,
not in the program.

## How to run

```bash
# from the repository root — the pinned core is fetched and verified first
bash e2e/run_all.sh
```

The e2e leg (`e2e/app_a.sh`) boots the app on BOTH backends
(`METALOGOS_SERVE_BACKEND=interpreter` then `=vm`), runs the full restart
arc per backend, and diffs the transcripts (`assert_identical`, §2.4).
The nightly workflow adds the stress leg (`e2e/nightly_app_a.sh`): 5
notes surviving 3 restarts, per backend.

## The parity proof (recorded)

Both transcripts from a green local run of the pinned core v0.30.1
(27877b8) — identical, TW == VM:

```
[app-a] --- TW transcript ---        [app-a] --- VM transcript ---
persist: persisted:greeting          persist: persisted:greeting
query1: showcase-note-v1             query1: showcase-note-v1
list: contains greeting              list: contains greeting
query2: showcase-note-v1             query2: showcase-note-v1
```

`query2 == query1` on BOTH backends — the state survived the restart;
the transcripts are byte-identical — the §2.4 parity holds. The CI
re-proves this on every PR and every push to main.

The nightly stress leg (the same pinned core): `5 notes survived 3
restarts` on the interpreter AND on the VM, `parity OK (app-a-nightly):
TW == VM`.

## Boundaries

- Offline-only (ADR-0190 §2.2): no live providers, no external network —
  the only network touch in CI is the pinned-core fetch (the fixture
  delivery).
- The fixed 64-hex master key in the e2e is TEST-ONLY (the anchored form
  the core's №520 e2e pins); it is not a secret.
- The serve rate limit (the default 100 req/min per client) is respected
  by both legs' request volume.
- The showcase is NOT a GFI (№561) and adds no language constructs (§4).
