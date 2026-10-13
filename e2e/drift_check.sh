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

# e2e/drift_check.sh — the NON-BLOCKING weekly drift-check (naryad №679,
# ADR-0190 §3(а) sync answer: «pin + scheduled drift-check»).
#
# Compares the pin (core-pin.txt) with the core repository's latest
# published release. ALWAYS exits 0 — this check never fails a build and
# never auto-bumps the pin; it reports, the owner decides. Output is plain
# markdown, designed to be appended to the GitHub step summary.

set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${HERE}/lib.sh"
load_pin

# The API call is best-effort: on ANY failure (rate limit, network) the
# check reports "unknown" and exits 0 — it never fails a build. In GitHub
# Actions GITHUB_TOKEN raises the rate limit; locally it stays anonymous.
auth=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi

latest_tag=""
if resp="$(curl -fsSL "${auth[@]}" "https://api.github.com/repos/${CORE_REPO}/releases/latest" 2>/dev/null)"; then
  latest_tag="$(printf '%s' "${resp}" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)"
fi

echo "## Core drift-check"
echo ""
echo "| | |"
echo "|---|---|"
echo "| Pinned core | \`${CORE_TAG}\` (\`${CORE_SHA}\`) |"

if [[ -z "${latest_tag}" ]]; then
  echo "| Latest release | **unknown** (GitHub API returned no release) |"
  echo "| Verdict | ⚠️ could not determine the drift — inspect manually |"
  exit 0
fi

echo "| Latest release | \`${latest_tag}\` |"

if [[ "${latest_tag}" == "${CORE_TAG}" ]]; then
  echo "| Verdict | ✅ in sync — the showcase sits on the latest published core |"
else
  echo "| Verdict | 🔎 **DRIFT**: the core moved \`${CORE_TAG}\` → \`${latest_tag}\`. |"
  echo ""
  echo "Bumping the pin is a small PR that carries the both-backend proof of"
  echo "every app on the new pin (ADR-0190 §2.4) — never a silent bump."
fi
