# app-b-bot — STUB (loudly empty)

**This directory is empty by design.** The bot application has not landed
yet.

- **Owner:** naryad №681 (P1, examples) — [Metalogos- gh#1232](https://github.com/ShkodnikAI/Metalogos-/issues/1232), Wave 42.
- **What will live here:** a bot skeleton per ADR-0190 §2.2 — poll/hook
  intake + a small dialog state machine in mlog + one outbound call behind
  the deterministic stub (`send_message` without a bot token logs to
  `[AUDIT]` — no network), packaged as an mlogpkg project.
- **The e2e oracle:** the scripted dialog transcript — stable across runs,
  offline, identical on both backends (TW and VM).
- **Until then:** there is no app here, nothing to run, and the CI passes
  precisely because the harness reports this stub loudly instead of
  pretending to test something.

Do not place unrelated files here. The owner naryad fills this directory.
