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

# e2e/run_all.sh — the BLOCKING both-backend e2e harness of the showcase
# (naryad №679, Wave 42; ADR-0190 §2.4 + §3(а)).
#
# Contract:
#   1. Fetch and verify the pinned core binary (core-pin.txt: SHA256 +
#      BUILD-INFO source commit). A wrong core invalidates every proof.
#   2. Discover legs: e2e/app_*.sh run always; e2e/nightly_*.sh run only
#      when RUN_NIGHTLY=1 (the nightly workflow sets it).
#   3. Each leg receives MLOG_BIN (the verified pinned binary) and the leg
#      itself must run its TW and VM arcs and diff them (assert_identical).
#   4. With zero legs (the stub state after №679) the harness reports the
#      stubs LOUDLY — owner naryads named — and exits 0. It never pretends
#      to have tested something.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"
load_pin

echo "[e2e] showcase e2e — pin ${CORE_TAG} (${CORE_SHA})"
MLOG_BIN="$(ensure_core_bin)"
export MLOG_BIN
echo "[e2e] core binary verified: ${MLOG_BIN}"

shopt -s nullglob
legs=()
for f in "${HERE}"/app_*.sh; do legs+=("$f"); done
if [[ "${RUN_NIGHTLY:-0}" == "1" ]]; then
  for f in "${HERE}"/nightly_*.sh; do legs+=("$f"); done
fi
shopt -u nullglob

if [[ ${#legs[@]} -eq 0 ]]; then
  echo "[e2e] ─────────────────────────────────────────────────────────────"
  echo "[e2e] STUB STATE — no application legs are registered yet."
  echo "[e2e]   app-a-serve/     → owner naryad №680 (Metalogos- gh#1231)"
  echo "[e2e]   app-b-bot/       → owner naryad №681 (Metalogos- gh#1232)"
  echo "[e2e]   app-c-llm-agent/ → owner naryad №682 (Metalogos- gh#1233)"
  echo "[e2e] The pin and the harness are verified; the apps are loudly"
  echo "[e2e] absent (see the STUB READMEs). Exiting 0 — the CI is green"
  echo "[e2e] on the scaffold, and it will turn RED the moment a leg"
  echo "[e2e] exists and fails."
  echo "[e2e] ─────────────────────────────────────────────────────────────"
  exit 0
fi

status=0
for leg in "${legs[@]}"; do
  echo "[e2e] ▶ leg: $(basename "${leg}")"
  if ! bash "${leg}"; then
    echo "[e2e] ✗ leg FAILED: $(basename "${leg}")" >&2
    status=1
  else
    echo "[e2e] ✓ leg passed: $(basename "${leg}")"
  fi
done

if [[ ${status} -ne 0 ]]; then
  echo "[e2e] RESULT: FAILED (a leg failed or a parity divergence was found — STOP per ADR-0190 §2.4)" >&2
  exit 1
fi
echo "[e2e] RESULT: all ${#legs[@]} leg(s) green, both-backend parity proven."
