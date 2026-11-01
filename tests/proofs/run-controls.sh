#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# run-controls.sh — prove the proof-witness instrument works BOTH ways.
#
# standards/3-practice/PROOF-POLICY.adoc §7 requires a policy gate to be
# verified "both ways": it passes conforming input AND fails a deliberately
# planted violation. A gate that has only ever been seen to pass is
# indistinguishable from one that cannot fail.
#
# This script runs the whole verification in two halves:
#
#   1. run-ledger-controls.sh — 15 controls over the RECORDED claims (grades,
#      statements, flags, history, unclaimed witnesses, escape hatches). No
#      prover needed: that half runs everywhere.
#   2. the kernel controls below — a closed Rocq proof and a closed Lean proof
#      must be accepted by their kernels, and Print Assumptions / #print axioms
#      must report them closed and axiom-free. This half exists because a
#      compiler's exit code is not evidence of a closed proof: Rocq accepts
#      `Admitted` and Lean accepts `sorry` with status 0.
#
# The fixtures live in tests/proofs/control/. They are NOT estate proofs and
# they sit outside verification/proofs/, so no census, ledger or catalogue ever
# counts them as mathematics.
#
# Exit: 0 every control behaved as required; 1 an expectation was violated;
#       2 BLOCKED — a prover the controls need is not installed here.
#       BLOCKED is never reported as a pass (PROOF-POLICY §6).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

CONTROLS="tests/proofs/control"
VIOLATIONS=0
CHECKS=0
ok()   { CHECKS=$((CHECKS + 1)); echo "  ✅ $*"; }
viol() { echo "  ❌ $*"; VIOLATIONS=$((VIOLATIONS + 1)); }

echo "=== Proof-witness instrument controls (PROOF-POLICY §7, both ways) ==="
echo ""

# --- 1. the recorded-claim half ---------------------------------------------
if bash tests/proofs/run-ledger-controls.sh; then
  :
else
  echo "  ✗ the ledger-form controls failed; the instrument does not behave as claimed."
  VIOLATIONS=$((VIOLATIONS + 1))
fi
echo ""

# --- 2/3. the kernel half: absent means BLOCKED, never a pass ---------------
echo "=== Kernel controls (need coqc, coqtop and lean) ==="
missing=()
for tool in coqc coqtop lean; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "BLOCKED: the kernel controls need ${missing[*]} on PATH, and the instrument"
  echo "         cannot be shown to work without them. This is NOT a pass (PROOF-POLICY §6)."
  exit 2
fi
echo "coqc: $(coqc --version 2>/dev/null | head -1)"
echo "lean: $(lean --version 2>/dev/null | head -1)"
echo ""

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cp "$CONTROLS/Control.v" "$WORK/Control.v"
if ( cd "$WORK" && coqc -q Control.v ) >"$WORK/coqc-control.log" 2>&1; then
  ok "K1. coqc accepts the closed control (Control.v)"
else
  viol "K1. coqc rejected the closed control; the instrument is broken, not strict"
  sed 's/^/      /' "$WORK/coqc-control.log" | head -20
fi
assumptions="$( cd "$WORK" && printf 'Require Import Control.\nPrint Assumptions control_true.\n' | coqtop -quiet 2>&1 )"
if printf '%s' "$assumptions" | grep -q "Closed under the global context"; then
  ok "K2. Print Assumptions reports the closed control as closed"
else
  viol "K2. Print Assumptions did not report 'Closed under the global context'"
  printf '%s\n' "$assumptions" | sed 's/^/      /' | head -20
fi

cp "$CONTROLS/PlantedAdmitted.v" "$WORK/PlantedAdmitted.v"
if ( cd "$WORK" && coqc -q PlantedAdmitted.v ) >"$WORK/coqc-planted.log" 2>&1; then
  # Coq accepts Admitted at compile time; that is exactly why an exit code is
  # not evidence. The scan must catch it (control L2), and the kernel must not
  # report it closed (K3).
  echo "  ℹ️  coqc accepts the planted Admitted control — exit code alone is not evidence (informational, not counted)"
else
  echo "  ℹ️  coqc rejected the planted Admitted control outright (informational, not counted)"
fi
planted_assumptions="$( cd "$WORK" && printf 'Require Import PlantedAdmitted.\nPrint Assumptions planted_true.\n' | coqtop -quiet 2>&1 )"
if printf '%s' "$planted_assumptions" | grep -q "Closed under the global context"; then
  viol "K3. the kernel reported the Admitted control as closed — axiom tracking is blind"
else
  ok "K3. the kernel does not report the Admitted control as closed"
fi

lean_clean="$( cd "$CONTROLS" && lean Control.lean 2>&1 )"
if printf '%s' "$lean_clean" | grep -q "does not depend on any axioms"; then
  ok "K4. #print axioms reports the closed Lean control as axiom-free"
else
  viol "K4. #print axioms did not report the closed Lean control as axiom-free"
  printf '%s\n' "$lean_clean" | sed 's/^/      /' | head -20
fi
lean_planted="$( cd "$CONTROLS" && lean PlantedSorry.lean 2>&1 )"
if printf '%s' "$lean_planted" | grep -q "sorryAx"; then
  ok "K5. #print axioms exposes sorryAx in the planted Lean control"
else
  viol "K5. #print axioms did not expose sorryAx — Lean axiom tracking is blind"
  printf '%s\n' "$lean_planted" | sed 's/^/      /' | head -20
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS control expectation(s) violated — the instrument does not behave as"
  echo "      claimed, so a green proof lane would mean nothing."
  exit 1
fi
echo "PASS: every control behaved as required — the instrument passes what should pass"
echo "      and fails what must fail ($CHECKS kernel expectation(s); the ledger-form"
echo "      controls reported their own count above)."
# Machine-readable evidence: annotations are retrievable through the check-run
# API, so "how many expectations actually ran?" is answerable without the raw
# runner log (which GitHub does not serve to every client).
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof-witness kernel controls verified both ways (§7): $CHECKS expectation(s), 0 violations, coqc $(coqc --version | head -1), lean $(lean --version | head -1)"
fi
exit 0
