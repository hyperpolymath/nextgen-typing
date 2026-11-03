#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Aspect tests for nextgen-typing (cross-cutting architectural invariants):
#   1. SPDX compliance — all verification proofs and gate scripts have SPDX headers
#   2. Dangerous proof escape hatches — scripts/proof-scan-dangerous.sh passes
#   3. Coordination boundary — scripts/check-coordination-boundary.sh passes
#   4. Proof enrolment & ledger — scripts/check-proof-enrolment.sh & check-proof-ledger.sh pass

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

PASS=0
FAIL=0
WARN=0

green() { printf '\033[32m%s\033[0m\n' "$*"; }
red()   { printf '\033[31m%s\033[0m\n' "$*"; }
yellow(){ printf '\033[33m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

pass() { green "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { red "  FAIL: $1"; FAIL=$((FAIL + 1)); }
warn() { yellow "  WARN: $1"; WARN=$((WARN + 1)); }

echo "═══════════════════════════════════════════════════════════════"
echo "  nextgen-typing — Aspect Tests (Cross-Cutting Concerns)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

bold "Aspect 1: SPDX license headers"
MISSING_SPDX=0
while IFS= read -r -d '' f; do
    if ! head -5 "$f" | grep -q "SPDX-License-Identifier"; then
        warn "Missing SPDX header: $f"
        MISSING_SPDX=$((MISSING_SPDX + 1))
    fi
done < <(find scripts/ verification/proofs/ -type f \( -name "*.agda" -o -name "*.v" -o -name "*.lean" -o -name "*.idr" -o -name "*.sh" \) -print0 2>/dev/null)

if [[ "$MISSING_SPDX" -eq 0 ]]; then
    pass "All verification proofs and gate scripts carry SPDX headers"
else
    fail "$MISSING_SPDX file(s) missing SPDX headers"
fi

bold "Aspect 2: Dangerous proof escape hatches"
if ./scripts/proof-scan-dangerous.sh >/dev/null; then
    pass "Comment-aware proof escape-hatch scanner clean"
else
    fail "scripts/proof-scan-dangerous.sh reported dangerous proof tokens"
fi

bold "Aspect 3: Coordination boundary"
if ./scripts/check-coordination-boundary.sh >/dev/null; then
    pass "Coordination boundary intact (verification/proofs/ only)"
else
    fail "scripts/check-coordination-boundary.sh failed"
fi

bold "Aspect 4: Proof enrolment & ledger integrity"
ENROL_RC=0
./scripts/check-proof-enrolment.sh >/dev/null 2>&1 || ENROL_RC=$?
if [[ "$ENROL_RC" -eq 0 || "$ENROL_RC" -eq 2 ]] && ./scripts/check-proof-ledger.sh >/dev/null; then
    pass "Proof enrolment consistent and LEDGER.json audit passed"
else
    fail "Proof enrolment (rc=$ENROL_RC) or LEDGER.json check failed"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
printf "  Results: PASS=%d  FAIL=%d  WARN=%d\n" "$PASS" "$FAIL" "$WARN"
echo "═══════════════════════════════════════════════════════════════"

[[ "$FAIL" -eq 0 ]]
