#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# run-ledger-controls.sh — the ledger/scan half of the both-ways verification of
# the proof instrument (standards/3-practice/PROOF-POLICY.adoc §7).
#
# These controls need no prover: they exercise the rules that decide whether a
# RECORDED claim is honest — the escape-hatch scan, the grade/evidence
# arithmetic, statement and flag drift, and the history rules of mathesis §6.
# The kernel-level half (a closed proof accepted, `Admitted`/`sorry` rejected by
# the kernel's own axiom query) needs coqc and lean and lives in
# run-controls.sh, which calls this script first.
#
# Every control that must FAIL is checked for the specific refusal, not just for
# a non-zero exit: a gate that fails for the wrong reason is not doing its job.
#
# Exit: 0 all controls behaved; 1 an expectation was violated; 2 BLOCKED (a
#       tool the controls need — jq — is missing).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

CONTROLS="tests/proofs/control"
GATE="scripts/check-proof-ledger.sh"
LEDGER="verification/proofs/LEDGER.json"

VIOLATIONS=0
CHECKS=0
ok()   { CHECKS=$((CHECKS + 1)); echo "  ✅ $*"; }
viol() { echo "  ❌ $*"; VIOLATIONS=$((VIOLATIONS + 1)); }

command -v jq >/dev/null 2>&1 || {
  echo "BLOCKED: these controls need jq to plant violations; not found on PATH." >&2
  exit 2
}
[ -f "$LEDGER" ] || { echo "BLOCKED: no ledger at $LEDGER" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "=== Ledger-form controls (no prover needed) ==="

# expect_refusal <label> <pattern> <ledger-file> [needs a repo copy: yes/no]
expect_refusal() {
  local label="$1" pattern="$2" file="$3" log="$WORK/log.txt"
  if bash "$GATE" --ledger "$file" >"$log" 2>&1; then
    viol "$label — the gate ACCEPTED it"
    return
  fi
  if grep -qF -- "$pattern" "$log"; then
    ok "$label — refused: ${pattern:0:78}..."
  else
    viol "$label — failed for the wrong reason (expected '$pattern')"
    sed 's/^/      /' "$log" | grep -E '^      ' | head -5
  fi
}

# --- scan: a real escape hatch is refused, a closed proof is not ------------
if bash "$GATE" --scan-file "$CONTROLS/Control.v" >/dev/null 2>&1; then
  ok "1. the escape-hatch scan accepts a closed Rocq proof (no false positive)"
else
  viol "1. the escape-hatch scan rejected a closed Rocq proof (false positive)"
fi
if bash "$GATE" --scan-file "$CONTROLS/PlantedAdmitted.v" >/dev/null 2>&1; then
  viol "2. the escape-hatch scan ACCEPTED a proof closed with Admitted"
else
  ok "2. the escape-hatch scan rejects a proof closed with Admitted"
fi
if bash "$GATE" --scan-file "$CONTROLS/Control.lean" >/dev/null 2>&1; then
  ok "3. the escape-hatch scan accepts a closed Lean proof (no false positive)"
else
  viol "3. the escape-hatch scan rejected a closed Lean proof (false positive)"
fi
if bash "$GATE" --scan-file "$CONTROLS/PlantedSorry.lean" >/dev/null 2>&1; then
  viol "4. the escape-hatch scan ACCEPTED a proof closed with sorry"
else
  ok "4. the escape-hatch scan rejects a proof closed with sorry"
fi

# --- grades and evidence ----------------------------------------------------
jq '(.theorems[0].grade) = "2i"' "$LEDGER" > "$WORK/grade-2i.json"
expect_refusal "5. a grade 2i claim with no proven leg" \
  "grade 2i requires exactly one proven recheck leg" "$WORK/grade-2i.json"

jq '(.theorems[0].history) = [{"date":"2026-11-01","target":"grade","from":"3","to":"2ii","evidence":"planted"}]' \
  "$LEDGER" > "$WORK/grade-history.json"
expect_refusal "6. a history whose last grade contradicts the ledger" \
  "history's last recorded grade is '2ii'" "$WORK/grade-history.json"

jq '(.theorems[0].history) = [{"date":"2026-11-01","target":"grade","from":"2i","to":"3","evidence":"re-audit; the leg never existed","reason":"the earlier grade counted a leg with no witness"}]' \
  "$LEDGER" > "$WORK/grade-regressed.json"
if bash "$GATE" --ledger "$WORK/grade-regressed.json" >/dev/null 2>&1; then
  ok "7. an honest, evidenced regression is accepted (the rules cut both ways)"
else
  viol "7. an honest, evidenced regression was refused — the history rule is too strict"
fi

jq '(.theorems[0].history) = [{"date":"2026-11-01","target":"grade","from":"2i","to":"3","evidence":"planted"}]' \
  "$LEDGER" > "$WORK/grade-no-reason.json"
expect_refusal "8. a regression with no recorded reason" \
  "regressed from '2i' to '3' with no .reason" "$WORK/grade-no-reason.json"

jq '(.theorems[0].source.safety_flags) -= ["--without-K"]' "$LEDGER" > "$WORK/flags.json"
expect_refusal "9. recorded flags that drift from the ones in force" \
  "effective safety flags recorded as" "$WORK/flags.json"

jq '(.theorems[0].statement_formal.declarations[0].type) = "affine-weakening echo-true ≡ affine-weakening echo-TRUE"' \
  "$LEDGER" > "$WORK/statement.json"
expect_refusal "10. a recorded statement that the Agda file no longer contains" \
  "statement drifted" "$WORK/statement.json"

jq '(.theorems[0].source.escape_hatch_evidence) = ""' "$LEDGER" > "$WORK/no-evidence.json"
expect_refusal "11. 'no postulates' asserted with no mechanism behind it" \
  "no .escape_hatch_evidence" "$WORK/no-evidence.json"

jq 'del(.theorems[0].grade_deviation)' "$LEDGER" > "$WORK/no-deviation.json"
expect_refusal "12. non-standard flags with the deviation left unrecorded" \
  "neither of the configurations mathesis §5 names" "$WORK/no-deviation.json"

jq '(.theorems[0].statement_anchor) += ["TP-ECHO-9"]' "$LEDGER" > "$WORK/anchor.json"
expect_refusal "13. a statement anchored to a declaration that does not exist" \
  "statement anchor 'TP-ECHO-9' is not declared" "$WORK/anchor.json"

jq '(.theorems[0].source.files) += ["verification/proofs/agda/Ghost.agda"]' "$LEDGER" > "$WORK/ghost-source.json"
expect_refusal "14. a source file that is not on disk" \
  "source file recorded but missing on disk" "$WORK/ghost-source.json"

# --- a witness on disk that nothing claims ----------------------------------
sandbox="$WORK/repo"
mkdir -p "$sandbox"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox" && tar -xf - )
printf 'Theorem unlisted_witness : True.\nProof. exact I. Qed.\n' \
  > "$sandbox/verification/proofs/coq/UnlistedWitness.v"
if ( cd "$sandbox" && bash scripts/check-proof-ledger.sh ) >"$WORK/unlisted.log" 2>&1; then
  viol "15. the gate ACCEPTED a witness that is in neither the ledger nor the MANIFEST"
elif grep -qF "witness on disk is not claimed in the ledger" "$WORK/unlisted.log"; then
  ok "15. a witness on disk that no ledger row claims is refused, and named"
else
  viol "15. the unclaimed-witness control failed for the wrong reason"
  sed 's/^/      /' "$WORK/unlisted.log" | tail -5
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS ledger-form control expectation(s) violated."
  exit 1
fi
echo "PASS: $CHECKS ledger-form expectation(s) held."
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof ledger controls: $CHECKS expectation(s), 0 violations (grades, statements, flags, history, unclaimed witnesses)"
fi
exit 0
