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
# e2e/app_b.sh — the BLOCKING leg of App B, the bot on mlogpkg
# (naryad №681, Wave 42; ADR-0190 §2.2 + §2.4).
#
# Three parts:
#   1. The mlogpkg surface: the manifest shape validated, and the source
#      semantic-checked via `mlog check` — the same check_program family
#      `mlogpkg build` runs. The mlogpkg BINARY is not part of the pinned
#      release assets (only mlog-linux-x86_64 is released), so the leg
#      exercises exactly the surface the pin carries; the mapping is
#      documented in app-b-bot/README.md (the honest boundary).
#   2. The serve arcs: HOOK intake (immediate updates) + POLL intake
#      (enqueue → poll → drain → queue empty) through the dialog state
#      machine, on BOTH backends; transcripts byte-identical (§2.4).
#   3. The outbound stub: send_message answers [AUDIT] lines in the
#      server log (TELEGRAM_BOT_TOKEN unset — the deterministic stub);
#      asserted by presence per backend.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"

[[ -n "${MLOG_BIN:-}" ]] || { echo "[app-b] FATAL: MLOG_BIN is not set (run via e2e/run_all.sh)" >&2; exit 1; }

APP_DIR="${HERE}/../app-b-bot"
PROGRAM="src/main.mlog"
MANIFEST="mlog.toml"
PORT=8792 # the port declared in main.mlog — single source of truth
WORK="$(mktemp -d)"
cleanup() {
  # The leg owns exactly one process family: the mlog servers serving
  # THIS app's program (matched by the full command line, its own path
  # only — never other apps' legs).
  pkill -f "serve .*app-b-bot/${PROGRAM}" 2>/dev/null || true
  rm -rf "${WORK}"
}
trap cleanup EXIT

# ── part 1: the mlogpkg surface ──────────────────────────────────────
grep -q '^name = "showcase-bot"$' "${APP_DIR}/${MANIFEST}" \
  || { echo "[app-b] FATAL: ${MANIFEST} must name the showcase-bot package" >&2; exit 1; }
grep -q '^version = ' "${APP_DIR}/${MANIFEST}" \
  || { echo "[app-b] FATAL: ${MANIFEST} must carry a version" >&2; }
echo "[app-b] manifest: ${MANIFEST} OK (name + version)"

"${MLOG_BIN}" check "${APP_DIR}/${PROGRAM}" > "${WORK}/check.txt" 2>&1 \
  || { echo "[app-b] FATAL: mlog check failed (the mlogpkg-build semantic-check family):" >&2; cat "${WORK}/check.txt" >&2; exit 1; }
echo "[app-b] mlog check: OK (the mlogpkg build's semantic-check family)"
lines=$(wc -l < "${APP_DIR}/${PROGRAM}")
echo "[app-b] ${PROGRAM}: ${lines} lines"

# self-healing: clear any stale server of THIS program before the first boot
pkill -f "serve .*app-b-bot/${PROGRAM}" 2>/dev/null || true
sleep 1

serve_app() { # serve_app <backend> <db>
  METALOGOS_SERVE_BACKEND="$1" METALOGOS_MEMORY_DB="$2" \
    METALOGOS_MEMORY_MASTER="b7c2d4a16f83e5924a0d7c6b8f1e3a5d9c0b2e4f6a8d1c3b5e7f9a2c4d6e8f0b" \
    TELEGRAM_BOT_TOKEN= \
    "${MLOG_BIN}" serve "${APP_DIR}/${PROGRAM}" > "${WORK}/server-$1.log" 2>&1 &
  SERVER_PID=$!
}

wait_ready() { # wait_ready — poll until /hook answers 200 (a real update)
  local i code
  for i in $(seq 1 20); do
    code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
      -d '{"chat":"probe","text":"x"}' "http://127.0.0.1:${PORT}/hook" 2>/dev/null || true)
    [[ "${code}" == "200" ]] && return 0
    sleep 0.5
  done
  return 1
}

serve_with_retry() { # serve_with_retry <backend> <db>
  local backend="$1" db="$2" tries=0
  serve_app "${backend}" "${db}"
  until wait_ready; do
    tries=$((tries + 1))
    [[ ${tries} -ge 3 ]] && {
      echo "[app-b] FATAL (${backend}): the server did not become ready on :${PORT}" >&2
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

post() { # post <path> <body> — echo the route response
  curl -s -X POST -d "$2" "http://127.0.0.1:${PORT}$1"
}

run_arc() { # run_arc <backend> <transcript> — hook + poll arcs
  local backend="$1" transcript="$2"
  local db="${WORK}/typed-${backend}.db"
  rm -f "${db}"

  serve_with_retry "${backend}" "${db}"

  # HOOK intake — the dialog state machine, per-chat independence
  echo "hook u1 start: $(post /hook '{"chat":"u1","text":"start"}')" >> "${transcript}"
  echo "hook u1 help:  $(post /hook '{"chat":"u1","text":"help"}')"  >> "${transcript}"
  echo "hook u1 ping:  $(post /hook '{"chat":"u1","text":"ping"}')"  >> "${transcript}"
  echo "hook u2 hi:    $(post /hook '{"chat":"u2","text":"hi"}')"    >> "${transcript}"

  # POLL intake — enqueue, drain, then the honest empty answer
  echo "enqueue u3 start: $(post /enqueue '{"chat":"u3","text":"start"}')" >> "${transcript}"
  echo "enqueue u3 help:  $(post /enqueue '{"chat":"u3","text":"help"}')"  >> "${transcript}"
  echo "poll 1: $(post /poll '{}')" >> "${transcript}"
  echo "poll 2: $(post /poll '{}')" >> "${transcript}"
  echo "poll 3: $(post /poll '{}')" >> "${transcript}"

  stop_server

  # the outbound stub — presence per backend (the [AUDIT] line is the
  # deterministic stub answer without TELEGRAM_BOT_TOKEN; the expected
  # count is 7: 1 readiness probe + 4 hook sends + 2 poll sends)
  local stubs
  stubs=$(grep -c "\[AUDIT\] send_message" "${WORK}/server-${backend}.log" || true)
  if [[ "${stubs}" -ge 7 ]]; then
    echo "audit-stub: present (${stubs} sends)" >> "${transcript}"
  else
    echo "[app-b] FATAL (${backend}): the [AUDIT] send_message stub lines are missing (${stubs}, expected >= 7)" >&2
    exit 1
  fi

  echo "[app-b] ${backend}: hook + poll arcs OK"
}

# Sequential legs: the port is declared in main.mlog (8792).
run_arc interpreter "${WORK}/transcript-tw.txt"
run_arc vm         "${WORK}/transcript-vm.txt"

echo "[app-b] --- TW transcript ---"
cat "${WORK}/transcript-tw.txt"
echo "[app-b] --- VM transcript ---"
cat "${WORK}/transcript-vm.txt"

# §2.4 parity: the transcripts must be identical on both backends.
assert_identical "app-b" "${WORK}/transcript-tw.txt" "${WORK}/transcript-vm.txt"
