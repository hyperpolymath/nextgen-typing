#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# run-ledger-controls.sh — the ledger/scan half of the both-ways verification of
# the proof instrument (metadatastician/standards 3-practice/PROOF-POLICY.adoc
# §7).
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

# --- the trust base beyond this repo ---------------------------------------
jq '(.theorems[0].source.assumptions[] | select(.name == "absolute-zero") | .undischarged_axioms) = 61
    | (.theorems[0].caveats) |= map(select(test("absolute-zero") | not))'   "$LEDGER" > "$WORK/no-az-caveat.json"
expect_refusal "15. an external dependency with 61 undischarged axioms and no caveat naming it" \
  "but no entry in .caveats names it" "$WORK/no-az-caveat.json"

jq '(.theorems[0].source.import_cone.modules[0].postulates) = 2' \
  "$LEDGER" > "$WORK/cone.json"
expect_refusal "16. a postulated module inside the import cone while the leg claims 'proven'" \
  "cannot be 'proven'" "$WORK/cone.json"

jq '(.theorems[0].source.assumptions[] | select(.name == "echo-types")) |= del(.evidence)' \
  "$LEDGER" > "$WORK/no-evidence-ext.json"
expect_refusal "17. a claim about another repository with no evidence of where it was read" \
  "records no evidence" "$WORK/no-evidence-ext.json"

jq '(.theorems[0].caveats) = []' "$LEDGER" > "$WORK/no-caveats.json"
expect_refusal "18. open legs with no caveat at all (a claim by omission)" \
  "say in the record that the theorem is not fully rechecked" "$WORK/no-caveats.json"

# --- the authority the audit is against -------------------------------------
jq 'del(.policy.proof_policy.commit)' "$LEDGER" > "$WORK/unpinned.json"
expect_refusal "20. a policy cited by name but not pinned to a commit" \
  "must be the full 40-character commit" "$WORK/unpinned.json"

jq '(.policy.proof_policy.vendored_here) = true' "$LEDGER" > "$WORK/vendored-lie.json"
expect_refusal "21. a vendored copy claimed where this tree has no copy" \
  "there is no file at" "$WORK/vendored-lie.json"

# --- §4 waivers and §2.2 routes --------------------------------------------
jq '(.theorems[0].legs[0].status) = "proven" | (.theorems[0].legs[0].waiver) = {"obligation":"lean leg","tool":"lean4","reason":"statement uses a universe the lean fragment cannot express","record":"PROOF-STATUS.adoc#waivers"}' \
  "$LEDGER" > "$WORK/waiver-with-status.json"
expect_refusal "22. a waiver used as a softer status token" \
  "a waiver is not a status token" "$WORK/waiver-with-status.json"

jq '(.theorems[0].legs[0]) |= (del(.status, .route, .artifact) | .waiver = {"obligation":"rocq leg","tool":"rocq"})' \
  "$LEDGER" > "$WORK/waiver-thin.json"
expect_refusal "23. a waiver that gives no reason and no exception record" \
  "waiver without 'reason'" "$WORK/waiver-thin.json"

jq '(.theorems[0].legs[0].route) = "unavailable"' "$LEDGER" > "$WORK/unavailable-silent.json"
expect_refusal "24. a route declared 'unavailable' with nothing said about what is missing" \
  "with no blocker recorded" "$WORK/unavailable-silent.json"

jq '(.theorems[0].legs[0]) |= (.status = "proven" | .route = "unavailable"
      | .artifact = "verification/proofs/agda/EchoTyping.agda")' \
  "$LEDGER" > "$WORK/unavailable-proven.json"
expect_refusal "25. a route that does not exist, carrying a proven status" \
  "cannot support a claim" "$WORK/unavailable-proven.json"

# A CONFORMING waiver must be accepted, and must be visible in the verdict.
jq '(.theorems[0].legs[0]) |= (del(.status, .route, .artifact)
     | .waiver = {"obligation":"rocq leg","tool":"rocq",
                   "reason":"statement uses --cubical-compatible universes with no Rocq counterpart",
                   "record":"PROOF-STATUS.adoc#waivers"})' \
  "$LEDGER" > "$WORK/waiver-ok.json"
if bash scripts/check-proof-ledger.sh --ledger "$WORK/waiver-ok.json" >"$WORK/waiver-ok.log" 2>&1 \
   && grep -qF "waived legs" "$WORK/waiver-ok.log"; then
  ok "26. a conforming waiver is accepted AND printed in the verdict, not buried"
else
  viol "26. a conforming waiver was refused, or was accepted without being reported"
  sed 's/^/      /' "$WORK/waiver-ok.log" | tail -5
fi

# --- a witness on disk that nothing claims ----------------------------------
sandbox="$WORK/repo"
mkdir -p "$sandbox"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox" && tar -xf - )
printf 'Theorem unlisted_witness : True.\nProof. exact I. Qed.\n' \
  > "$sandbox/verification/proofs/coq/UnlistedWitness.v"
if ( cd "$sandbox" && bash scripts/check-proof-ledger.sh ) >"$WORK/unlisted.log" 2>&1; then
  viol "19. the gate ACCEPTED a witness that is in neither the ledger nor the MANIFEST"
elif grep -qF "witness on disk is not claimed in the ledger" "$WORK/unlisted.log"; then
  ok "19. a witness on disk that no ledger row claims is refused, and named"
else
  viol "19. the unclaimed-witness control failed for the wrong reason"
  sed 's/^/      /' "$WORK/unlisted.log" | tail -5
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS ledger-form control expectation(s) violated."
  exit 1
fi
echo "PASS: $CHECKS ledger-form expectation(s) held."
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof ledger controls: $CHECKS expectation(s), 0 violations (grades, statements, flags, history, trust base, policy pin, waivers, unclaimed witnesses)"
fi
exit 0
