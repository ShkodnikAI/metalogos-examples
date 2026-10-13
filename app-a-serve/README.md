# app-a-serve — STUB (loudly empty)

**This directory is empty by design.** The stateful serve application has
not landed yet.

- **Owner:** naryad №680 (P1, examples) — [Metalogos- gh#1231](https://github.com/ShkodnikAI/Metalogos-/issues/1231), Wave 42.
- **What will live here:** one `.mlog` program (≤120 lines) demonstrating
  state through the serve contour per ADR-0190 §2.1 — typed memory
  (`memory_open`/`memory_put`/`memory_read`) + kv + `mlogserver` routes +
  the persistence env (`METALOGOS_MEMORY_DB`, `METALOGOS_MEMORY_MASTER`).
- **The e2e oracle:** `persist → query → restart → query` — the state
  survives the restart, the second query returns what the first wrote,
  identical on both backends (TW and VM), with the parity proof recorded in
  this README.
- **Until then:** there is no app here, nothing to run, and the CI passes
  precisely because the harness reports this stub loudly instead of
  pretending to test something.

Do not place unrelated files here. The owner naryad fills this directory.
