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

# e2e/lib.sh — shared helpers for the metalogos-examples harness.
# Sourced by e2e/run_all.sh, the per-app legs and e2e/fetch_core.sh.
# The header form above is the core repository's LICENSE-APACHE appendix
# form, taken verbatim from the pinned tag v0.30.1 (27877b8) — see the
# charter README, "License".

# Fail loudly on every error, on every unset variable, on every failed pipe.
set -euo pipefail

E2E_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "${E2E_DIR}")"
PIN_FILE="${REPO_ROOT}/core-pin.txt"
CACHE_DIR="${MLOG_CACHE_DIR:-${REPO_ROOT}/.cache}"

# load_pin — read the pin file into CORE_* variables (exported).
load_pin() {
  # shellcheck disable=SC1090
  source "${PIN_FILE}"
  export CORE_REPO CORE_TAG CORE_SHA CORE_ASSET CORE_ASSET_SHA256
}

# ensure_core_bin — download and verify the pinned release binary once per
# cache; echo the binary path. Fail-loud on any checksum or BUILD-INFO
# mismatch: a silently wrong core would invalidate every parity proof.
ensure_core_bin() {
  load_pin
  mkdir -p "${CACHE_DIR}"
  local bin="${CACHE_DIR}/${CORE_ASSET}"
  local build_info="${CACHE_DIR}/BUILD-INFO.txt"
  local sums="${CACHE_DIR}/SHA256SUMS"
  local base="https://github.com/${CORE_REPO}/releases/download/${CORE_TAG}"

  if [[ ! -x "${bin}" ]]; then
    echo "[e2e] fetching pinned core ${CORE_TAG} (${CORE_SHA}) …" >&2
    curl -fsSL -o "${bin}"        "${base}/${CORE_ASSET}"
    curl -fsSL -o "${sums}"       "${base}/SHA256SUMS"
    curl -fsSL -o "${build_info}" "${base}/BUILD-INFO.txt"
    chmod +x "${bin}"
  fi

  # --status: no output on success (the path below must stay the ONLY
  # stdout line — callers capture it in command substitution).
  ( cd "${CACHE_DIR}" && echo "${CORE_ASSET_SHA256}  ${CORE_ASSET}" | sha256sum --status -c - ) \
    || { echo "[e2e] FATAL: pinned core checksum mismatch" >&2; exit 1; }

  grep -q "source commit: ${CORE_SHA}" "${build_info}" \
    || { echo "[e2e] FATAL: BUILD-INFO source commit != pin ${CORE_SHA}" >&2; exit 1; }

  # Only the path goes to stdout — progress goes to stderr — so callers can
  # safely capture the result in command substitution.
  echo "${bin}"
}

# run_tw <dir> <file.mlog> [args...] — run a program on the tree-walking
# interpreter (mlog run <file.mlog>).
run_tw() {
  local dir="$1" file="$2"; shift 2
  ( cd "${dir}" && "${MLOG_BIN}" run "${file}" "$@" )
}

# run_vm <dir> <file.mlog> [args...] — compile to .mbc and run on the
# bytecode VM. Compiles into a scratch copy so the source tree never gains
# build artifacts.
run_vm() {
  local dir="$1" file="$2"; shift 2
  local scratch
  scratch="$(mktemp -d)"
  cp "${dir}/${file}" "${scratch}/"
  ( cd "${scratch}" && "${MLOG_BIN}" compile "${file}" >/dev/null \
      && "${MLOG_BIN}" run "${file%.mlog}.mbc" "$@" )
  rm -rf "${scratch}"
}

# assert_identical <label> <tw_out> <vm_out> — diff the TW and VM outputs of
# a leg; a divergence is the loudest possible showcase finding (ADR-0190
# §2.4): the leg must STOP and fail, never adjust the oracle.
assert_identical() {
  local label="$1" tw_out="$2" vm_out="$3"
  if ! diff -u "${tw_out}" "${vm_out}"; then
    echo "[e2e] PARITY FAILURE (${label}): TW and VM outputs diverge — STOP per ADR-0190 §2.4, do not adjust the oracle, flag the conveyor." >&2
    exit 1
  fi
  echo "[e2e] parity OK (${label}): TW == VM"
}
