# e2e/README.md — the shared both-backend e2e harness (naryad №679).

## What lives here

| File | Role |
|---|---|
| `lib.sh` | shared helpers: pin loading, pinned-binary fetch + SHA256/BUILD-INFO verification, `run_tw`, `run_vm`, `assert_identical` |
| `fetch_core.sh` | standalone fetch/verify of the pinned core binary (prints the path) |
| `run_all.sh` | the BLOCKING harness: verify the pin, then run every leg |
| `drift_check.sh` | the NON-BLOCKING weekly drift report (always exits 0) |
| `app_*.sh` | per-app blocking legs: `app_a.sh` (№680), `app_b.sh` (№681), `app_c.sh` (№682) |
| `nightly_*.sh` | nightly-only legs — run when `RUN_NIGHTLY=1` |

## The leg contract

Each `e2e/app_<name>.sh`:

1. receives `MLOG_BIN` — the verified pinned core binary (run_all.sh sets it);
2. runs its app's arc **twice** — TW via `run_tw` and VM via `run_vm`
   (or the serve contour twice with `METALOGOS_SERVE_BACKEND=interpreter`
   and `=vm`);
3. diffs the two outputs with `assert_identical` — a divergence STOPS the
   build (ADR-0190 §2.4: never adjust the oracle, flag the conveyor);
4. is **offline-only**: no network dependency ever enters the blocking path
   (ADR-0190 §2.2). Live-provider demos stay manual, outside CI.

## The stub state (historical, after №679)

With zero legs registered, `run_all.sh` exits 0 **loudly**: it names the
application stubs and their owner naryads (№680, №681, №682). The green
run on the scaffold proved the pin + harness, and nothing else — by
design. Since №680–№682 all three legs are registered, the stub branch is
unreachable in practice, and any failing leg turns the CI red.
