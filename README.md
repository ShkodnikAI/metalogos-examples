# metalogos-examples — the METALOGOS showcase

Three small, runnable applications with an honest end-to-end proof, written
for the language **consumer**. The charter is
[ADR-0190](https://github.com/ShkodnikAI/Metalogos-/blob/main/docs/adr/0190-examples-showcase.md)
(`docs/adr/0190-examples-showcase.md` in the core repository); this
repository implements it. If you are asking «what can I build with
METALOGOS?» — start here, run the apps, read their transcripts.

## What this repository is — and is not

- It **is** the consumer-facing showcase: three curated applications with
  e2e oracles, runnable on both language backends, offline by default.
- It is **not** the developer-facing `examples/` library of the core
  repository (497 files that exercise constructs, edge cases and regressions,
  with the GFI #951 golden-sidecar line). The showcase duplicates neither
  that library nor its track — a file that lives there has no reason to be
  here, and vice versa.
- It is **not** a GFI channel (naryad №561): the conveyor does not file
  good-first-issues against the showcase.

## The three showcase applications (ADR-0190 §2)

| App | Directory | Owner (core repo) | Bounded subset | e2e oracle |
|---|---|---|---|---|
| **A — stateful serve** | `app-a-serve/` | naryad №680 (gh#1231) | typed memory (`memory_open`/`memory_put`/`memory_read`) + kv + `mlogserver` routes + the persistence env (`METALOGOS_MEMORY_DB`, `METALOGOS_MEMORY_MASTER`) | `persist → query → restart → query`: the state survives the restart and the second query returns what the first wrote — identical on both backends |
| **B — bot on mlogpkg** | `app-b-bot/` | naryad №681 (gh#1232) | poll intake + a dialog state machine in mlog + one outbound call behind the deterministic stub (`send_message` without a bot token → the `[AUDIT]` stub) | the scripted dialog transcript, stable across runs and identical on both backends |
| **C — small LLM agent** | `app-c-llm-agent/` | naryad №682 (gh#1233) | `call_llm` + one tool call + the visible action trace, under `METALOGOS_MOCK_LLM=1` (deterministic canned-model circuit) | the agent transcript (model calls, tool calls, actions), identical on both backends |

All three application directories have landed with their owner naryads
(№680, №681, №682); each app README carries the both-backend parity proof
of its bounded subset.

## The honesty rule (ADR-0190 §2.4)

**An application in the showcase runs on BOTH backends — the tree-walking
interpreter (TW) and the bytecode VM — on its bounded subset, and the e2e
must prove it.** The bounded subset of each app is chosen exactly so that
this parity holds today; the parity proof is recorded in the app's README,
not asserted from memory.

A cross-backend divergence found in a showcase app is the loudest possible
finding: **stop the commit, flag the conveyor — never adjust the oracle.**
Widening an app's bounded subset is a small PR that carries the fresh
both-backend proof.

## Core pin policy (ADR-0190 §3(а), the sync answer)

The showcase pins the core instead of floating with it:

- the pin lives in [`core-pin.txt`](core-pin.txt): **v0.30.1**
  (`27877b811187bd9c064545e97a35fcd8e12881c2`), release asset
  `mlog-linux-x86_64`, SHA256 recorded;
- CI downloads the pinned release binary, verifies its SHA256 and checks the
  release `BUILD-INFO.txt` source commit — the same commit as the pin —
  before any e2e leg runs;
- a **weekly scheduled drift-check** (non-blocking) compares the pin against
  the core's latest release and reports the drift in the job summary;
- bumping the pin is a small PR that carries the both-backend proof of every
  app on the new pin — never a silent version bump.

## Layout

```
app-a-serve/     # App A — stateful serve (naryad №680) — LANDED
app-b-bot/       # App B — bot on mlogpkg (naryad №681) — LANDED
app-c-llm-agent/ # App C — small LLM agent (naryad №682) — LANDED
e2e/             # the shared both-backend e2e harness (this naryad №679);
                 # legs: app_a.sh, app_b.sh, app_c.sh
core-pin.txt     # the pinned core: tag, commit, asset checksum
LICENSE-APACHE   # Apache-2.0, verbatim from the pinned core tag
LICENSE-MIT      # MIT, verbatim from the pinned core tag
```

## CI

Two workflows, both in this repository (the core CI cell does not grow —
naryad №535; the second CI is sanctioned by ADR-0190 §3(а)):

- **`ci.yml` (blocking)** — on every push and PR: fetch and verify the
  pinned core binary, then run `e2e/run_all.sh`, which executes every
  registered app leg on **both backends** and diffs their outputs. All
  blocking legs are **offline-only** (ADR-0190 §2.2): no network dependency
  ever enters the blocking path. Live providers, when an app documents one,
  stay a manual local run outside CI.
- **`drift-check.yml` (non-blocking)** — weekly schedule: compare
  `core-pin.txt` with the core repository's latest release; report the drift
  in the job summary. Never fails the build, never auto-bumps the pin.

## License

Licensed under either [Apache-2.0](LICENSE-APACHE) or [MIT](LICENSE-MIT) at
your option — the same dual-license setup as the core repository (the
§-answers on the charter, answer 3: «as in the main repo»). Every source
file in this repository carries the license header form of the core
repository, taken verbatim from the pinned tag `v0.30.1` (`27877b8`) of the
core's `LICENSE-APACHE` appendix: `Copyright 2024-2026 ShkodnikAI` plus the
standard Apache notice, in the comment syntax of the file's format.
