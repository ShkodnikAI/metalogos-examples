# Copyright 2024-2026 ShkodnikAI
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# e2e/app_c.sh — the BLOCKING leg of App C, the small LLM agent
# (naryad №682, Wave 42; ADR-0190 §2.3 + §2.4).
#
# The oracle arc, in order:
#   1. the honesty boundary — WITHOUT METALOGOS_MOCK_LLM the agent
#      refuses loudly (rc != 0, EMPTY stdout) before any model call;
#      nothing is invented, the leg stays offline;
#   2. the TW arc of the full agent cycle (two tasks, two model calls
#      each, exactly one tool call per cycle);
#   3. the VM arc (compile + run);
#   4. the visible-trace markers: the model calls 1/2 and 2/2, the tool
#      calls, the final answer — and BOTH dispatches
#      math_api.double(21) = 42 and math_api.square(21) = 441;
#   5. parity — the full transcripts (stdout AND stderr) must be
#      byte-identical TW == VM (§2.4: a divergence is the loudest
#      possible showcase finding — STOP, never adjust the oracle).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"

[[ -n "${MLOG_BIN:-}" ]] || { echo "[app-c] FATAL: MLOG_BIN is not set (run via e2e/run_all.sh)" >&2; exit 1; }

APP_DIR="${HERE}/../app-c-llm-agent"
PROGRAM="agent.mlog"
WORK="$(mktemp -d)"
cleanup() { rm -rf "${WORK}"; }
trap cleanup EXIT

# The line budget of the naryad is checked, not assumed: >120 lines =
# rework, never a budget widening (the App A form).
lines=$(wc -l < "${APP_DIR}/${PROGRAM}")
[[ "${lines}" -le 120 ]] \
  || { echo "[app-c] FATAL: ${PROGRAM} is ${lines} lines (budget 120) — rework, do not widen the budget" >&2; exit 1; }
echo "[app-c] ${PROGRAM}: ${lines} lines (budget 120)"

# The static gate first: check must be green on BOTH-backend semantics.
"${MLOG_BIN}" check "${APP_DIR}/${PROGRAM}" > "${WORK}/check.txt" 2>&1 \
  || { echo "[app-c] FATAL: mlog check failed:" >&2; cat "${WORK}/check.txt" >&2; exit 1; }
echo "[app-c] mlog check: OK"

# ── 1. the honesty boundary: no mock contour → loud refusal ─────────
rc=0
env -u METALOGOS_MOCK_LLM "${MLOG_BIN}" run "${APP_DIR}/${PROGRAM}" \
  > "${WORK}/nomock.out" 2> "${WORK}/nomock.err" || rc=$?
[[ "${rc}" -ne 0 ]] \
  || { echo "[app-c] FATAL: without METALOGOS_MOCK_LLM the agent must refuse loudly (rc != 0)" >&2; exit 1; }
[[ ! -s "${WORK}/nomock.out" ]] \
  || { echo "[app-c] FATAL: stdout must be EMPTY on the refusal — nothing is invented:" >&2; cat "${WORK}/nomock.out" >&2; exit 1; }
grep -q "METALOGOS_MOCK_LLM" "${WORK}/nomock.err" \
  || { echo "[app-c] FATAL: the refusal must name the missing contour variable" >&2; cat "${WORK}/nomock.err" >&2; exit 1; }
echo "[app-c] honesty boundary: no mock contour -> loud refusal (rc=${rc}, stdout empty)"

# ── 2+3. both-backend arcs of the full cycle ─────────────────────────
export METALOGOS_MOCK_LLM=1
run_tw "${APP_DIR}" "${PROGRAM}" > "${WORK}/tw.out" 2> "${WORK}/tw.err" \
  || { echo "[app-c] FATAL: the TW arc failed" >&2; cat "${WORK}/tw.err" >&2; exit 1; }
run_vm "${APP_DIR}" "${PROGRAM}" > "${WORK}/vm.out" 2> "${WORK}/vm.err" \
  || { echo "[app-c] FATAL: the VM arc failed (compile or run)" >&2; cat "${WORK}/vm.err" >&2; exit 1; }
unset METALOGOS_MOCK_LLM
echo "[app-c] TW arc and VM arc: both green"

# ── 4. the visible-trace markers (on the TW transcript; parity gives
#      the same to the VM transcript byte-for-byte) ────────────────────
assert_marker() { # assert_marker <file> <needle> <what>
  grep -qF -- "$2" "$1" \
    || { echo "[app-c] FATAL: the trace marker is missing ($3): '$2'" >&2; cat "$1" >&2; exit 1; }
}
assert_marker "${WORK}/tw.out" "agent final:" "the flow output carries the final answer"
assert_marker "${WORK}/tw.err" "model call 1/2" "the task model call is on the trace"
assert_marker "${WORK}/tw.err" "model call 2/2" "the report model call is on the trace"
assert_marker "${WORK}/tw.err" "action verb: double" "the parsed action verb (double)"
assert_marker "${WORK}/tw.err" "action verb: square" "the parsed action verb (square)"
assert_marker "${WORK}/tw.err" "tool call: math_api.double(21) = 42" "the dispatch double"
assert_marker "${WORK}/tw.err" "tool call: math_api.square(21) = 441" "the dispatch square"
assert_marker "${WORK}/tw.err" "final answer" "the final-answer trace step"
echo "[app-c] visible trace: model calls 1/2 + 2/2, action verbs, BOTH dispatches (42, 441), final answer"

# ── 5. parity: full transcripts byte-identical TW == VM ──────────────
assert_identical "app-c stdout" "${WORK}/tw.out" "${WORK}/vm.out"
assert_identical "app-c stderr" "${WORK}/tw.err" "${WORK}/vm.err"

echo "[app-c] RESULT: the agent leg is green — honesty boundary + both-backend parity proven."
