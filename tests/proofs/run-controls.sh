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
# The controls are tiny fixtures under tests/proofs/control/. They are NOT
# estate proofs and they live outside verification/proofs/, so no census, no
# ledger and no catalogue ever counts them as mathematics.
#
# Assertions:
#   1. Rocq   closed control      -> coqc accepts, Print Assumptions: closed
#   2. Rocq   planted `Admitted`  -> escape-hatch scan REJECTS it, and the
#                                    kernel does not report it closed
#   3. Lean 4 closed control      -> lean accepts, #print axioms: no axioms
#   4. Lean 4 planted `sorry`     -> #print axioms shows sorryAx, scan REJECTS
#   5. Ledger gate                -> rejects a planted "grade 2i, legs open"
#                                    claim (no evidence behind the grade)
#   6. Ledger gate                -> rejects a witness planted on disk but not
#                                    claimed in the ledger or the MANIFEST
#
# Exit: 0 every control behaved as required; 1 an expectation was violated;
#       2 BLOCKED — a prover the controls need is not installed here.
#       BLOCKED is never reported as a pass (PROOF-POLICY §6).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

CONTROLS="tests/proofs/control"
GATE="scripts/check-proof-ledger.sh"
LEDGER="verification/proofs/LEDGER.json"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

VIOLATIONS=0
CHECKS=0
ok()   { CHECKS=$((CHECKS + 1)); echo "  ✅ $*"; }
viol() { echo "  ❌ $*"; VIOLATIONS=$((VIOLATIONS + 1)); }

echo "=== Proof-witness instrument controls (PROOF-POLICY §7, both ways) ==="
echo "fixtures: $CONTROLS"
echo ""

# --- toolchain: absent means BLOCKED, never a pass ---------------------------
missing=()
for tool in coqc coqtop lean; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "BLOCKED: the controls need ${missing[*]} on PATH, and the instrument cannot"
  echo "         be shown to work without them. This is NOT a pass (PROOF-POLICY §6)."
  exit 2
fi
echo "coqc: $(coqc --version 2>/dev/null | head -1)"
echo "lean: $(lean --version 2>/dev/null | head -1)"
echo ""

# --- 1/2. Rocq: closed proof accepted, planted Admitted rejected ------------
cp "$CONTROLS/Control.v" "$WORK/Control.v"
if ( cd "$WORK" && coqc -q Control.v ) >"$WORK/coqc-control.log" 2>&1; then
  ok "1. coqc accepts the closed control (Control.v)"
else
  viol "1. coqc rejected the closed control; the instrument is broken, not strict"
  sed 's/^/      /' "$WORK/coqc-control.log" | head -20
fi
assumptions="$( cd "$WORK" && printf 'Require Import Control.\nPrint Assumptions control_true.\n' | coqtop -quiet 2>&1 )"
if printf '%s' "$assumptions" | grep -q "Closed under the global context"; then
  ok "1. Print Assumptions reports the closed control as closed"
else
  viol "1. Print Assumptions did not report 'Closed under the global context'"
  printf '%s\n' "$assumptions" | sed 's/^/      /' | head -20
fi

cp "$CONTROLS/PlantedAdmitted.v" "$WORK/PlantedAdmitted.v"
if ( cd "$WORK" && coqc -q PlantedAdmitted.v ) >"$WORK/coqc-planted.log" 2>&1; then
  # Coq accepts Admitted at compile time; that is exactly why an exit code is
  # not evidence. The scan must catch it.
  ok "2. coqc accepts the planted Admitted control (exit code alone is not evidence)"
else
  ok "2. coqc rejected the planted Admitted control outright"
fi
if bash "$GATE" --scan-file "$CONTROLS/PlantedAdmitted.v" >/dev/null 2>&1; then
  viol "2. the escape-hatch scan ACCEPTED a proof closed with Admitted"
else
  ok "2. the escape-hatch scan rejects the planted Admitted control"
fi
if bash "$GATE" --scan-file "$CONTROLS/Control.v" >/dev/null 2>&1; then
  ok "2. the escape-hatch scan accepts the closed control (no false positive)"
else
  viol "2. the escape-hatch scan rejected the closed control (false positive)"
fi
planted_assumptions="$( cd "$WORK" && printf 'Require Import PlantedAdmitted.\nPrint Assumptions planted_true.\n' | coqtop -quiet 2>&1 )"
if printf '%s' "$planted_assumptions" | grep -q "Closed under the global context"; then
  viol "2. the kernel reported the Admitted control as closed — axiom tracking is blind"
else
  ok "2. the kernel does not report the Admitted control as closed"
fi

# --- 3/4. Lean 4: closed proof accepted, planted sorry detected -------------
lean_clean="$( cd "$CONTROLS" && lean Control.lean 2>&1 )"
if printf '%s' "$lean_clean" | grep -q "does not depend on any axioms"; then
  ok "3. #print axioms reports the closed Lean control as axiom-free"
else
  viol "3. #print axioms did not report the closed Lean control as axiom-free"
  printf '%s\n' "$lean_clean" | sed 's/^/      /' | head -20
fi
lean_planted="$( cd "$CONTROLS" && lean PlantedSorry.lean 2>&1 )"
if printf '%s' "$lean_planted" | grep -q "sorryAx"; then
  ok "4. #print axioms exposes sorryAx in the planted Lean control"
else
  viol "4. #print axioms did not expose sorryAx — Lean axiom tracking is blind"
  printf '%s\n' "$lean_planted" | sed 's/^/      /' | head -20
fi
if bash "$GATE" --scan-file "$CONTROLS/PlantedSorry.lean" >/dev/null 2>&1; then
  viol "4. the escape-hatch scan ACCEPTED a proof closed with sorry"
else
  ok "4. the escape-hatch scan rejects the planted Lean sorry control"
fi
if bash "$GATE" --scan-file "$CONTROLS/Control.lean" >/dev/null 2>&1; then
  ok "4. the escape-hatch scan accepts the closed Lean control (no false positive)"
else
  viol "4. the escape-hatch scan rejected the closed Lean control (false positive)"
fi

# --- 5. a grade with no evidence behind it must be refused ------------------
jq '(.theorems[0].grade) = "2i"' "$LEDGER" > "$WORK/planted-grade.json"
if bash "$GATE" --ledger "$WORK/planted-grade.json" >"$WORK/planted-grade.log" 2>&1; then
  viol "5. the ledger gate ACCEPTED a grade 2i claim with no translated leg"
else
  ok "5. the ledger gate refuses a grade 2i claim with no proven leg behind it"
fi
if grep -q "grade 2i requires exactly one proven recheck leg" "$WORK/planted-grade.log"; then
  ok "5. and it says which clause was violated"
else
  viol "5. the ledger gate failed for an unexpected reason"
  sed 's/^/      /' "$WORK/planted-grade.log" | tail -10
fi

# --- 6. a witness on disk with no ledger row must be refused ---------------
sandbox="$WORK/repo"
mkdir -p "$sandbox"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox" && tar -xf - )
printf 'Theorem unlisted_witness : True.\nProof. exact I. Qed.\n' \
  > "$sandbox/verification/proofs/coq/UnlistedWitness.v"
if ( cd "$sandbox" && bash scripts/check-proof-ledger.sh ) >"$WORK/unlisted.log" 2>&1; then
  viol "6. the ledger gate ACCEPTED a witness that is in neither the ledger nor the MANIFEST"
else
  ok "6. the ledger gate refuses an unlisted witness on disk"
fi
if grep -q "witness on disk is not claimed in the ledger" "$WORK/unlisted.log"; then
  ok "6. and it names the unclaimed witness"
else
  viol "6. the unlisted-witness control failed for an unexpected reason"
  sed 's/^/      /' "$WORK/unlisted.log" | tail -10
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS control expectation(s) violated — the instrument does not behave as"
  echo "      claimed, so a green proof lane would mean nothing."
  exit 1
fi
echo "PASS: every control behaved as required — the instrument passes what should pass"
echo "      and fails what must fail ($CHECKS expectation(s))."
# Machine-readable evidence: annotations are retrievable through the check-run
# API, so "how many expectations actually ran?" is answerable without the raw
# runner log (which GitHub does not serve to every client).
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof-witness instrument verified both ways (§7): $CHECKS expectation(s), 0 violations, coqc $(coqc --version | head -1), lean $(lean --version | head -1)"
fi
exit 0
