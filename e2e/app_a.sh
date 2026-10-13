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
# e2e/app_a.sh — the BLOCKING leg of App A, the stateful serve application
# (naryad №680, Wave 42; ADR-0190 §2.1 + §2.4).
#
# The oracle arc: persist → query → restart → query, run on BOTH backends
# (METALOGOS_SERVE_BACKEND=interpreter then =vm, a fresh process each).
# The state must survive the restart (the typed-memory store re-opens and
# decrypts through METALOGOS_MEMORY_DB + METALOGOS_MEMORY_MASTER), and the
# TW/VM transcripts must be identical — a divergence is the loudest
# possible showcase finding (STOP, never adjust the oracle).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"

[[ -n "${MLOG_BIN:-}" ]] || { echo "[app-a] FATAL: MLOG_BIN is not set (run via e2e/run_all.sh)" >&2; exit 1; }

APP_DIR="${HERE}/../app-a-serve"
PROGRAM="serve.mlog"
WORK="$(mktemp -d)"
cleanup() {
  # The leg owns exactly one process family: the mlog servers serving THIS
  # app's program (matched by the full command line). A stale orphan from a
  # crashed earlier run must never poison the port — the leg cleans loudly
  # and narrowly (its own program path only, never other apps' legs).
  pkill -f "serve .*app-a-serve/${PROGRAM}" 2>/dev/null || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

# The fixed showcase master key (64 hex) — TEST-ONLY, anchors the
# typed-memory store so a FRESH PROCESS can decrypt after the restart
# (the №351 posture; the same anchored form the core's №520 e2e pins).
MASTER_HEX="ab5d1037f21c6e89b04a55c2d3e71f689c4b2a77e0d1c3f5a6b7c8d9e0f1a2b3"
NOTE_KEY="greeting"
NOTE_TEXT="showcase-note-v1"

# The line budget of the naryad is checked, not assumed: >120 lines =
# rework, never a budget widening.
lines=$(wc -l < "${APP_DIR}/${PROGRAM}")
[[ "${lines}" -le 120 ]] \
  || { echo "[app-a] FATAL: ${PROGRAM} is ${lines} lines (budget 120) — rework, do not widen the budget" >&2; exit 1; }
echo "[app-a] ${PROGRAM}: ${lines} lines (budget 120)"

# self-healing: clear any stale server of THIS program before the first boot
pkill -f "serve .*app-a-serve/${PROGRAM}" 2>/dev/null || true
sleep 1

serve_app() { # serve_app <backend> <db>
  METALOGOS_SERVE_BACKEND="$1" METALOGOS_MEMORY_DB="$2" METALOGOS_MEMORY_MASTER="${MASTER_HEX}" \
    TELEGRAM_BOT_TOKEN= \
    "${MLOG_BIN}" serve "${APP_DIR}/${PROGRAM}" > "${WORK}/server-$1.log" 2>&1 &
  SERVER_PID=$!
}

wait_ready() { # wait_ready <port> — poll until the total /notes route answers 200
  local i code
  for i in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
      -d '{}' "http://127.0.0.1:$1/notes" 2>/dev/null || true)
    [[ "${code}" == "200" ]] && return 0
    sleep 0.5
  done
  return 1
}

serve_with_retry() { # serve_with_retry <backend> <db> <port>
  local backend="$1" db="$2" port="$3" tries=0
  serve_app "${backend}" "${db}"
  until wait_ready "${port}"; do
    tries=$((tries + 1))
    [[ ${tries} -ge 3 ]] && {
      echo "[app-a] FATAL (${backend}): the server did not become ready on :${port}" >&2
      cat "${WORK}/server-${backend}.log" >&2 || true
      exit 1
    }
    echo "[app-a] (${backend}) serve attempt ${tries} failed — retrying" >&2
    kill "${SERVER_PID}" 2>/dev/null || true
    wait "${SERVER_PID}" 2>/dev/null || true
    sleep 3
    serve_app "${backend}" "${db}"
  done
}

stop_server() {
  kill "${SERVER_PID}" 2>/dev/null || true
  wait "${SERVER_PID}" 2>/dev/null || true
  SERVER_PID=""
}

run_arc() { # run_arc <backend> <transcript> — one full restart arc
  local backend="$1" transcript="$2"
  local port=8791 # the port declared in serve.mlog — single source of truth
  local db="${WORK}/typed-${backend}.db"
  rm -f "${db}"

  # ── boot 1 ──
  serve_with_retry "${backend}" "${db}" "${port}"

  # 1. persist
  local p q1 q2 keys
  p=$(curl -s -X POST -d "{\"key\":\"${NOTE_KEY}\",\"text\":\"${NOTE_TEXT}\"}" \
    "http://127.0.0.1:${port}/note")
  echo "persist: ${p}" >> "${transcript}"

  # 2. query (before the restart)
  q1=$(curl -s -X POST -d "{\"key\":\"${NOTE_KEY}\"}" "http://127.0.0.1:${port}/note/read")
  echo "query1: ${q1}" >> "${transcript}"

  # the list surface — a CONTAINS-check (the key order is not defined)
  keys=$(curl -s -X POST -d '{}' "http://127.0.0.1:${port}/notes")
  if [[ "${keys}" == *"${NOTE_KEY}"* ]]; then
    echo "list: contains ${NOTE_KEY}" >> "${transcript}"
  else
    echo "list: MISSING ${NOTE_KEY}" >> "${transcript}"
  fi

  # 3. RESTART — a genuinely fresh process over the same anchored store
  stop_server
  sleep 1
  serve_with_retry "${backend}" "${db}" "${port}"

  # 4. query (after the restart) — the state must have survived
  q2=$(curl -s -X POST -d "{\"key\":\"${NOTE_KEY}\"}" "http://127.0.0.1:${port}/note/read")
  echo "query2: ${q2}" >> "${transcript}"

  stop_server

  # the arc assertion: BOTH queries return exactly what was written
  if [[ "${q1}" != "${NOTE_TEXT}" || "${q2}" != "${NOTE_TEXT}" ]]; then
    echo "[app-a] FATAL (${backend}): the restart-persistence arc broke — query1='${q1}' query2='${q2}' (expected both '${NOTE_TEXT}')" >&2
    exit 1
  fi
  echo "[app-a] ${backend}: restart-persistence arc OK (persist → query → restart → query)"
}

# Sequential legs (the №496 pattern): the port is DECLARED in serve.mlog
# (8791), so the two backend arcs share it strictly sequentially — boot →
# restart → done, then the next backend. No overlap, no concurrency.
run_arc interpreter "${WORK}/transcript-tw.txt"
run_arc vm         "${WORK}/transcript-vm.txt"

echo "[app-a] --- TW transcript ---"
cat "${WORK}/transcript-tw.txt"
echo "[app-a] --- VM transcript ---"
cat "${WORK}/transcript-vm.txt"

# §2.4 parity: the transcripts must be identical on both backends.
assert_identical "app-a" "${WORK}/transcript-tw.txt" "${WORK}/transcript-vm.txt"
