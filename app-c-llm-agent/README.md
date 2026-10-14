# app-c-llm-agent — the small LLM agent (ADR-0190 §2.3)

A transparent agent loop on the deterministic mock circuit: one model
call + one tool call per cycle + the visible action trace. The owner is
naryad №682 (P2, examples) — [Metalogos-
gh#1233](https://github.com/ShkodnikAI/Metalogos-/issues/1233), Wave 42.

## Run it

```bash
# the deterministic offline circuit (no keys, no secrets, no network)
METALOGOS_MOCK_LLM=1 mlog run app-c-llm-agent/agent.mlog
# or the whole both-backend proof:
MLOG_BIN=/path/to/mlog bash e2e/run_all.sh   # runs every leg, App C included
```

Without `METALOGOS_MOCK_LLM=1|true` the agent **refuses loudly before
any model call** — nothing is invented, the real provider path is a
manual local run outside CI (ADR-0190 §2.2: live providers never enter
the blocking path).

## The agent cycle (per task)

1. **GUARD** — the mock contour is required
   (`METALOGOS_MOCK_LLM=1|true`); without it — a loud refusal naming the
   variable, stdout stays empty.
2. **MODEL CALL 1/2** — `call_llm("solve", task)`; the deterministic
   mock answers `"[MOCK: solve | <task>]"` (the №454/№478 canned
   circuit — fixed answers, byte-stable across runs).
3. **VALIDATION** — `escape_html` over the model text BEFORE any
   decision on it (the UNTRUSTED_DECISION rule: the agent never branches
   on raw model output).
4. **ACTION** — the action verb is parsed from the validated answer and
   exactly ONE tool call fires: `math_api.double(21)` or
   `math_api.square(21)` — the ADR-0054 qualified calls into a tool
   namespace.
5. **MODEL CALL 2/2** — the report call: the tool result goes back
   through the model; the trace shows it.

The scenario runs two tasks (`double`, `square`) over the seed 21; the
final answer is the flow output (stdout), every step is on the visible
trace (stderr).

## The transcript (deterministic, both backends identical)

```text
[print] [trace] [agent] model call 1/2: call_llm(solve, double)
[print] [trace] [agent] model answered: [MOCK: solve | double]
[print] [trace] [agent] validated: [MOCK: solve | double]
[print] [trace] [agent] action verb: double
[print] [trace] [agent] tool call: math_api.double(21) = 42
[print] [trace] [agent] model call 2/2: call_llm(report, ...)
[print] [trace] [agent] report answered: [MOCK: report | double(21) = 42]
[print] [trace] [agent] model call 1/2: call_llm(solve, square)
[print] [trace] [agent] model answered: [MOCK: solve | square]
[print] [trace] [agent] validated: [MOCK: solve | square]
[print] [trace] [agent] action verb: square
[print] [trace] [agent] tool call: math_api.square(21) = 441
[print] [trace] [agent] model call 2/2: call_llm(report, ...)
[print] [trace] [agent] report answered: [MOCK: report | square(21) = 441]
[print] [trace] [agent] final answer: agent final: double(21) = 42; square(21) = 441
```

stdout carries exactly one line — the final answer:
`agent final: double(21) = 42; square(21) = 441`.

## The e2e oracle (e2e/app_c.sh)

1. honesty boundary: no mock contour → loud refusal (rc ≠ 0, empty
   stdout, the refusal names the variable);
2. the TW arc of the full cycle;
3. the VM arc (compile + run);
4. the visible-trace markers: model calls 1/2 + 2/2, both action verbs,
   BOTH dispatches (`math_api.double(21) = 42`,
   `math_api.square(21) = 441`), the final answer;
5. parity: the full transcripts (stdout AND stderr) byte-identical
   TW == VM (§2.4).

## Parity note (the honest history)

The tool-namespace dispatch (`math_api.double(21)` from a pattern body)
is exactly the surface where the VM compiler and the TW interpreter
DIVERGED before core naryad №684 (Metalogos- gh#1244): the VM compile
refused `qualified call 'math_api.double()' — not found` while TW ran
fine. Per the wave rules (§2.4) the divergence STOPPED this naryad's
commit — the oracle was never adjusted. №684 fixed the core (the
tool-method resolution + the two latent compiler holes), the both-backend
proof on the fixed core is green, and this leg lands gated on the core
pin bump that carries №684.
