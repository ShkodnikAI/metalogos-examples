# app-c-llm-agent — STUB (loudly empty)

**This directory is empty by design.** The small LLM agent has not landed
yet.

- **Owner:** naryad №682 (P2, examples) — [Metalogos- gh#1233](https://github.com/ShkodnikAI/Metalogos-/issues/1233), Wave 42.
- **What will live here:** a transparent agent loop per ADR-0190 §2.3 — one
  model call + one tool call + the visible action trace, under
  `METALOGOS_MOCK_LLM=1` (the deterministic canned-model circuit; no keys,
  no secrets, no network).
- **The e2e oracle:** the agent transcript (model calls, tool calls,
  actions, final answer) — identical on both backends (TW and VM).
- **Live provider:** documented as a manual local run only — it never enters
  CI.
- **Until then:** there is no app here, nothing to run, and the CI passes
  precisely because the harness reports this stub loudly instead of
  pretending to test something.

Do not place unrelated files here. The owner naryad fills this directory.
