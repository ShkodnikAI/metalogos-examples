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
# e2e/nightly_app_a.sh — the NIGHTLY stress leg of App A (naryad №680;
# ADR-0190 §2.1: "the long restart/stress legs in the nightly").
#
# Runs ONLY when the nightly workflow sets RUN_NIGHTLY=1 (the harness
# contract of e2e/run_all.sh). The arc: several notes persisted, each read
# back, then THREE server restarts with every note re-read after each
# restart — per backend. The per-request volume stays under the serve
# rate limit (the default is 100 req/min per client).

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"

[[ -n "${MLOG_BIN:-}" ]] || { echo "[app-a-nightly] FATAL: MLOG_BIN is not set (run via e2e/run_all.sh with RUN_NIGHTLY=1)" >&2; exit 1; }

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

MASTER_HEX="ab5d1037f21c6e89b04a55c2d3e71f689c4b2a77e0d1c3f5a6b7c8d9e0f1a2b3"
RESTARTS=3
NOTES=("alpha" "beta" "gamma" "delta" "epsilon")
NOTE_PREFIX="nightly-note"

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
      echo "[app-a-nightly] FATAL (${backend}): the server did not become ready on :${port}" >&2
      cat "${WORK}/server-${backend}.log" >&2 || true
      exit 1
    }
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

run_stress() { # run_stress <backend>
  local backend="$1"
  local port=8791 # the port declared in serve.mlog — the legs share it sequentially
  local db="${WORK}/typed-${backend}.db"
  rm -f "${db}"
  local transcript="${WORK}/stress-${backend}.txt"
  : > "${transcript}"

  serve_with_retry "${backend}" "${db}" "${port}"

  local n r
  # persist every note and read each back once
  for n in "${NOTES[@]}"; do
    r=$(curl -s -X POST -d "{\"key\":\"${NOTE_PREFIX}-${n}\",\"text\":\"value-${n}\"}" \
      "http://127.0.0.1:${port}/note")
    echo "persist ${n}: ${r}" >> "${transcript}"
    r=$(curl -s -X POST -d "{\"key\":\"${NOTE_PREFIX}-${n}\"}" "http://127.0.0.1:${port}/note/read")
    [[ "${r}" == "value-${n}" ]] || {
      echo "[app-a-nightly] FATAL (${backend}): the first read of ${n} broke: '${r}'" >&2
      exit 1
    }
  done
  stop_server

  # every restart re-reads EVERY note — the whole set survives each one
  local k
  for k in $(seq 1 "${RESTARTS}"); do
    sleep 1
    serve_with_retry "${backend}" "${db}" "${port}"
    for n in "${NOTES[@]}"; do
      r=$(curl -s -X POST -d "{\"key\":\"${NOTE_PREFIX}-${n}\"}" "http://127.0.0.1:${port}/note/read")
      echo "restart${k} ${n}: ${r}" >> "${transcript}"
      [[ "${r}" == "value-${n}" ]] || {
        echo "[app-a-nightly] FATAL (${backend}): the note ${n} did not survive restart ${k}: '${r}'" >&2
        exit 1
      }
    done
    stop_server
  done

  echo "[app-a-nightly] ${backend}: ${#NOTES[@]} notes survived ${RESTARTS} restarts"
}

# Sequential legs: the port is declared in serve.mlog (8791) — the two
# backend stress arcs share it strictly sequentially.
run_stress interpreter
run_stress vm

# §2.4 parity: the deterministic per-key lines must be identical.
assert_identical "app-a-nightly" "${WORK}/stress-interpreter.txt" "${WORK}/stress-vm.txt"
