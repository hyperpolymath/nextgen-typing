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

bash "$GATE" --scan-file "$CONTROLS/PlantedAxiom.v" >"$WORK/axiom-scan.log" 2>&1
axiom_rc=$?
if [ "$axiom_rc" -eq 0 ]; then
  viol "29. the escape-hatch scan ACCEPTED a Coq 'Axiom' (estate core tier)"
elif [ "$axiom_rc" -eq 1 ] && grep -qF "FAIL" "$WORK/axiom-scan.log"; then
  ok "29. the escape-hatch scan rejects a Coq 'Axiom' — the estate core tier, which the scan previously missed"
else
  viol "29. the Axiom control failed for the wrong reason (exit $axiom_rc)"
fi

# --- comment syntax is per language, in the dangerous direction -------------
# `(* ... *)` is a comment in Coq and ordinary text in Lean. One shared list made
# the Lean case clean-looking; refusing the Coq case would be a false positive.
bash "$GATE" --scan-file "$CONTROLS/PlantedLeanBlockText.lean" >"$WORK/lean-block.log" 2>&1
lean_block_rc=$?
if [ "$lean_block_rc" -eq 0 ]; then
  viol "41. the scan ACCEPTED a Lean axiom hidden in Coq's block-comment delimiters"
elif [ "$lean_block_rc" -eq 1 ] && grep -qF "FAIL" "$WORK/lean-block.log"; then
  ok "41. Coq's (* *) is not a comment in Lean: an axiom written inside it is found"
else
  viol "41. the Lean block-comment control failed for the wrong reason (exit $lean_block_rc — a missing fixture or a BLOCKED scanner is not a finding)"
  sed 's/^/      /' "$WORK/lean-block.log" | tail -5
fi

# Lean has no `//` comment: `{ n // n = 0 }` is subtype notation, and a stripper
# that treated `//` as a comment would cut the line before the sorry behind it.
bash "$GATE" --scan-file "$CONTROLS/PlantedLeanSubtype.lean" >"$WORK/lean-subtype.log" 2>&1
lean_subtype_rc=$?
if [ "$lean_subtype_rc" -eq 0 ]; then
  viol "43. the scan ACCEPTED a sorry placed after Lean subtype notation"
elif [ "$lean_subtype_rc" -eq 1 ] && grep -qF "FAIL" "$WORK/lean-subtype.log"; then
  ok "43. Lean's { n // n = 0 } is notation, not a comment: the sorry behind it is found"
else
  viol "43. the Lean subtype control failed for the wrong reason (exit $lean_subtype_rc)"
  sed 's/^/      /' "$WORK/lean-subtype.log" | tail -5
fi
if bash "$GATE" --scan-file "$CONTROLS/ControlCommentAxiom.v" >"$WORK/coq-comment.log" 2>&1; then
  ok "42. the same delimiters ARE a comment in Coq: prose there is not a violation"
else
  viol "42. the scan rejected a Coq file whose only mention of Axiom is inside a comment"
  sed 's/^/      /' "$WORK/coq-comment.log" | tail -5
fi

# --- grades and evidence ----------------------------------------------------
jq '(.theorems[0].grade) = "2i"' "$LEDGER" > "$WORK/grade-2i.json"
expect_refusal "5. a grade 2i claim with no proven leg" \
  "grade 2i requires at least one independent proven recheck leg" "$WORK/grade-2i.json"

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

# The fixture must actually be silent: the leg carries a blocker in the ledger, so
# setting the route alone would leave the rule nothing to complain about (and an
# earlier version of this control passed only because a field-shift bug made the
# gate read the wrong column).
jq '(.theorems[0].legs[0]) |= (.route = "unavailable" | del(.blocker))' \
  "$LEDGER" > "$WORK/unavailable-silent.json"
expect_refusal "24. a route declared 'unavailable' with nothing said about what is missing" \
  "with no blocker recorded" "$WORK/unavailable-silent.json"

jq '(.theorems[0].legs[0]) |= (.status = "proven" | .route = "unavailable"
      | .artifact = "verification/proofs/agda/EchoTyping.agda")' \
  "$LEDGER" > "$WORK/unavailable-proven.json"
expect_refusal "25. a route that does not exist, carrying a proven status" \
  "cannot support a claim" "$WORK/unavailable-proven.json"

# A proven leg for a prover the lane cannot compile. Grade 2i ledgers may name
# Isabelle, SMT or TLA+; nothing in scripts/check-proofs.sh runs any of them, so
# such a leg must be refused rather than counted. The artifact is a real file on
# disk, which is exactly what made the old default branch look satisfied.
jq '(.theorems[0].legs[0]) |= (.prover = "isabelle" | .status = "proven"
      | .route = "transported"
      | .artifact = "tests/proofs/control/Control.v"
      | .axioms = [] | .statement_compared = "planted: statement comparison recorded")' \
  "$LEDGER" > "$WORK/unwired-prover.json"
expect_refusal "36. a proven leg for a prover the lane has no recipe for" \
  "for a prover the lane cannot compile" "$WORK/unwired-prover.json"

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

# A waiver record that does not resolve removes an obligation without a reason.
# Both fixtures keep the rest of the conforming waiver, so the only difference is
# the citation: a missing file, and an anchor the cited file does not contain.
jq '(.theorems[0].legs[0]) |= (del(.status, .route, .artifact)
     | .waiver = {"obligation":"rocq leg","tool":"rocq",
                   "reason":"planted: statement cannot be expressed",
                   "record":"does-not-exist"})' \
  "$LEDGER" > "$WORK/waiver-ghost.json"
expect_refusal "37. a waiver whose record names no file in the repository" \
  "does not resolve" "$WORK/waiver-ghost.json"

jq '(.theorems[0].legs[0]) |= (del(.status, .route, .artifact)
     | .waiver = {"obligation":"rocq leg","tool":"rocq",
                   "reason":"planted: statement cannot be expressed",
                   "record":"PROOF-STATUS.adoc#no-such-anchor-anywhere"})' \
  "$LEDGER" > "$WORK/waiver-anchor.json"
expect_refusal "38. a waiver citing an anchor the record does not contain" \
  "which does not occur in" "$WORK/waiver-anchor.json"

# --- related developments are neither assumptions nor evidence -------------
jq '(.theorems[0].source.related_developments[0].consumed_by_this_proof) = true' \
  "$LEDGER" > "$WORK/related-consumed.json"
expect_refusal "33. a sibling formalisation counted as consumed (double-counting)" \
  "then it belongs in .source.assumptions" "$WORK/related-consumed.json"

jq 'del(.theorems[0].source.related_developments[0].relation)' \
  "$LEDGER" > "$WORK/related-norelation.json"
expect_refusal "34. a related development with no stated relation" \
  "records no relation" "$WORK/related-norelation.json"

# --- corroboration cannot become a receipt ---------------------------------
jq '(.theorems[0].local_evidence[0].corroboration_only) = false' \
  "$LEDGER" > "$WORK/local-as-receipt.json"
expect_refusal "31. a local run promoted into the receipt" \
  "cannot stand in for the pinned receipt" "$WORK/local-as-receipt.json"

jq 'del(.theorems[0].local_evidence[0].toolchain)' \
  "$LEDGER" > "$WORK/local-no-toolchain.json"
expect_refusal "32. a local run that does not name its compiler" \
  "cannot be reproduced" "$WORK/local-no-toolchain.json"

# --- mathesis §6: receipt lineage ------------------------------------------
jq '(.theorems[0].source.evidence.historical_evidence[0]) |= del(.state)' \
  "$LEDGER" > "$WORK/unnamed-history.json"
expect_refusal "27. a superseded receipt kept without saying it is superseded" \
  "has no state" "$WORK/unnamed-history.json"

jq '(.theorems[0].source.evidence.historical_evidence[0].state) = "archived"' \
  "$LEDGER" > "$WORK/bogus-history.json"
expect_refusal "28. a receipt state outside mathesis §6's superseded | regressed" \
  "which is not one of superseded" "$WORK/bogus-history.json"

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

# --- estate trusted-base compliance ----------------------------------------
# docs/TRUSTED-BASE-REDUCTION-POLICY.adoc requires a proof-debt register in a
# proof-bearing repo. An absent register is indistinguishable from an unexamined
# repository, so the scan must fail on one.
sandbox2="$WORK/repo-debt"
mkdir -p "$sandbox2"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox2" && tar -xf - )
# Delete the register only. PROOF-NEEDS stays: it is a statement of what the
# proofs need, not a disposition table, so it must not be accepted in the
# register's place. Leaving it in place is what makes this control test the
# invariant instead of testing an empty directory.
rm -f "$sandbox2/docs/proof-debt.md" "$sandbox2/docs/proof-debt.adoc"
if ( cd "$sandbox2" && bash scripts/proof-scan-dangerous.sh ) >"$WORK/nodebt.log" 2>&1; then
  viol "30. the scan passed with no proof-debt register (TRUSTED-BASE-REDUCTION-POLICY)"
elif grep -qF "no proof-debt register" "$WORK/nodebt.log"; then
  ok "30. a proof-bearing repo with no proof-debt register is refused, not quietly passed"
else
  viol "30. the debt-register control failed for the wrong reason"
  sed 's/^/      /' "$WORK/nodebt.log" | tail -5
fi

# --- Coq's admit. is a listed marker, so it must be catchable --------------
# The pattern list names admit. explicitly. A boundary bug made that alternative
# unfirable (the full stop and the trailing \b exclude each other), so the scan
# reported a file closed with admit. as clean. The fixture exists to keep that
# alternative honest.
if bash "$GATE" --scan-file "$CONTROLS/PlantedAdmit.v" >"$WORK/admit-scan.log" 2>&1; then
  viol "35. the escape-hatch scan ACCEPTED a Coq proof closed with admit."
elif grep -qF "FAIL" "$WORK/admit-scan.log"; then
  ok "35. the escape-hatch scan rejects Coq's admit. — a listed marker that the pattern could not reach"
else
  viol "35. the admit. control failed for the wrong reason"
  sed 's/^/      /' "$WORK/admit-scan.log" | tail -5
fi

# An assumption tagged dependency-pin with no version and no commit pins
# nothing. It satisfies the "name your trust base" rule while constraining no
# version at all, which is how the Agda pin could be deleted and the audit stay
# green.
jq '(.theorems[0].source.assumptions[0]) |= del(.version)' \
  "$LEDGER" > "$WORK/unpinned-dep.json"
expect_refusal "40. a dependency-pin assumption that pins no version and no commit" \
  "records neither a version nor a commit" "$WORK/unpinned-dep.json"

# --- a page may not outrun the ledger, theorem by theorem -------------------
# The summary table is where PROOF-STATUS.adoc states a grade. The gate reads the
# row for each theorem and compares it with that theorem's own ledger grade, so
# one proven leg elsewhere cannot switch the comparison off.
sandbox3="$WORK/repo-docgrade"
mkdir -p "$sandbox3"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox3" && tar -xf - )
sed -i 's/^|XP-1 |theory |\*3\*/|XP-1 |theory |*2i*/' "$sandbox3/PROOF-STATUS.adoc"
if ( cd "$sandbox3" && bash scripts/check-proof-ledger.sh ) >"$WORK/docgrade.log" 2>&1; then
  viol "39. the gate ACCEPTED a page claiming Grade 2i for a theorem the ledger records at Grade 3"
elif grep -qF "but the ledger says Grade 3" "$WORK/docgrade.log"; then
  ok "39. a documented grade above the ledger's own is refused, per theorem"
else
  viol "39. the documented-grade control failed for the wrong reason"
  sed 's/^/      /' "$WORK/docgrade.log" | tail -5
fi

# --- witness assumption & reconciliation ledger controls (#131 + mathesis) ---
# 44. A quarantined MANIFEST entry cannot back a proven leg.
sandbox4="$WORK/repo-quarantine"
mkdir -p "$sandbox4"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox4" && tar -xf - )
printf '(* INSTRUMENT CONTROL *)\nTheorem tp1 : True. Proof. exact I. Qed.\n' \
  > "$sandbox4/verification/proofs/coq/QuarWitness.v"
printf 'verification/proofs/coq|QuarWitness.v|quarantine|known broken\n' \
  >> "$sandbox4/verification/proofs/coq/MANIFEST"
jq '(.theorems[0].grade) = "2i"
    | (.theorems[0].legs[0]) |= (.status = "proven" | .route = "re-proved"
        | .reproof_reason = "control"
        | .artifact = "verification/proofs/coq/QuarWitness.v"
        | .declarations = [{"anchor":"TP-ECHO-1","name":"tp1"},{"anchor":"TP-ECHO-2","name":"tp2"},{"anchor":"TP-ECHO-3","name":"tp3"}]
        | .axioms = [] | .statement_compared = "compared against EchoTyping.agda"
        | .evidence = {"kind":"ci-receipt","commit":"3cd185939179773f177b59e6fee360719695dfc7","date":"2026-11-01","run":"https://example.invalid/run/1","assumptions_output":"Closed under the global context"})' \
  "$sandbox4/verification/proofs/LEDGER.json" > "$sandbox4/verification/proofs/LEDGER.tmp"
mv "$sandbox4/verification/proofs/LEDGER.tmp" "$sandbox4/verification/proofs/LEDGER.json"
if ( cd "$sandbox4" && bash scripts/check-proof-ledger.sh ) >"$WORK/quarantine-leg.log" 2>&1; then
  viol "44. the gate ACCEPTED a proven leg backed by a quarantined MANIFEST entry"
elif grep -qF "is not listed as 'gated'" "$WORK/quarantine-leg.log"; then
  ok "44. a quarantined MANIFEST entry cannot back a proven leg"
else
  viol "44. the quarantined-leg control failed for the wrong reason"
  sed 's/^/      /' "$WORK/quarantine-leg.log" | tail -5
fi

# 45. sorryAx is never a permissible entry in legs[].axioms.
jq '(.theorems[0].grade) = "2i"
    | (.theorems[0].legs[1]) |= (.status = "proven-with-postulates" | .route = "re-proved"
        | .reproof_reason = "control"
        | .artifact = "tests/proofs/control/Control.lean"
        | .axioms = ["sorryAx"] | .statement_compared = "compared against EchoTyping.agda")' \
  "$LEDGER" > "$WORK/sorryax-ledger.json"
expect_refusal "45. sorryAx recorded as a declared axiom in .axioms" \
  "'sorryAx' is an incomplete-proof marker" "$WORK/sorryax-ledger.json"

# 46. boolean false is not a statement comparison.
jq '(.theorems[0].grade) = "2i"
    | (.theorems[0].legs[1]) |= (.status = "proven" | .route = "re-proved"
        | .reproof_reason = "control"
        | .artifact = "tests/proofs/control/Control.lean"
        | .axioms = [] | .statement_compared = false)' \
  "$LEDGER" > "$WORK/false-compared.json"
expect_refusal "46. statement_compared set to boolean false on a proven leg" \
  "requires an affirmative statement comparison" "$WORK/false-compared.json"

# 47. duplicating the source prover (agda) as a leg cannot promote Grade 3 to 2i.
jq '(.theorems[0].grade) = "2i"
    | (.theorems[0].legs) += [{"prover":"agda","family":"dtt","status":"proven","route":"transported","artifact":"verification/proofs/agda/EchoTyping.agda","axioms":[],"statement_compared":"self"}]' \
  "$LEDGER" > "$WORK/dup-source-prover.json"
expect_refusal "47. duplicating the source prover as a recheck leg to claim Grade 2i" \
  "grade 2i requires at least one independent proven recheck leg" "$WORK/dup-source-prover.json"

# 48. unmapped hyphenated Agda anchors on a proven Rocq leg are refused.
sandbox5="$WORK/repo-unmapped"
mkdir -p "$sandbox5"
tar --exclude=.git --exclude=target -cf - . 2>/dev/null | ( cd "$sandbox5" && tar -xf - )
printf '(* INSTRUMENT CONTROL *)\nTheorem tp1 : True. Proof. exact I. Qed.\n' \
  > "$sandbox5/verification/proofs/coq/ValidWitness.v"
printf 'verification/proofs/coq|ValidWitness.v|gated|control\n' \
  >> "$sandbox5/verification/proofs/coq/MANIFEST"
jq '(.theorems[0].grade) = "2i"
    | (.theorems[0].legs[0]) |= (.status = "proven" | .route = "re-proved"
        | .reproof_reason = "control"
        | .artifact = "verification/proofs/coq/ValidWitness.v"
        | .axioms = [] | .statement_compared = "compared against EchoTyping.agda"
        | .evidence = {"kind":"ci-receipt","commit":"3cd185939179773f177b59e6fee360719695dfc7","date":"2026-11-01","run":"https://example.invalid/run/1","assumptions_output":"Closed under the global context"})' \
  "$sandbox5/verification/proofs/LEDGER.json" > "$sandbox5/verification/proofs/LEDGER.tmp"
mv "$sandbox5/verification/proofs/LEDGER.tmp" "$sandbox5/verification/proofs/LEDGER.json"
if ( cd "$sandbox5" && bash scripts/check-proof-ledger.sh ) >"$WORK/unmapped-anchor.log" 2>&1; then
  viol "48. the gate ACCEPTED a proven Rocq leg leaving hyphenated Agda anchors unmapped"
elif grep -qF "is not a valid rocq identifier" "$WORK/unmapped-anchor.log"; then
  ok "48. hyphenated Agda anchors left unmapped on a proven Rocq leg are refused"
else
  viol "48. the unmapped-anchor control failed for the wrong reason"
  sed 's/^/      /' "$WORK/unmapped-anchor.log" | tail -5
fi

# 49. mathesis CROSS-PROVER-RECONCILIATION: bridge cannot claim RECONCILED while legs are open.
jq '(.theorems[0].reconciliation.bridge) = "RECONCILED"' "$LEDGER" > "$WORK/premature-reconciled.json"
expect_refusal "49. claiming bridge RECONCILED while target recheck legs remain open" \
  "requires independently verified Rocq and Lean targets" "$WORK/premature-reconciled.json"

# 50. swapping two anchors' types in statement_formal.declarations is caught.
jq '(.theorems[0].statement_formal.declarations[0].type) as $t0
    | (.theorems[0].statement_formal.declarations[1].type) as $t1
    | (.theorems[0].statement_formal.declarations[0].type) = $t1
    | (.theorems[0].statement_formal.declarations[1].type) = $t0' \
  "$LEDGER" > "$WORK/swapped-decl-types.json"
expect_refusal "50. swapping formal types between two declaration anchors" \
  "statement drifted" "$WORK/swapped-decl-types.json"

# 51. Imported-axiom fixtures carry zero lexical escape hatches (proving why #131
#     requires kernel assumption queries in check-proofs.sh, not lexical scan alone).
if bash "$GATE" --scan-file "$CONTROLS/ControlImportedAxiom.v" >/dev/null 2>&1 \
   && bash "$GATE" --scan-file "$CONTROLS/ControlImportedAxiom.lean" >/dev/null 2>&1; then
  ok "51. imported-axiom fixtures pass lexical scan (confirming why kernel assumption queries are necessary)"
else
  viol "51. imported-axiom fixtures unexpectedly tripped the lexical scan"
fi

echo ""
if [ "$VIOLATIONS" -gt 0 ]; then
  echo "FAIL: $VIOLATIONS ledger-form control expectation(s) violated."
  exit 1
fi
echo "PASS: $CHECKS ledger-form expectation(s) held."
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof ledger controls: $CHECKS expectation(s), 0 violations (grades, statements, flags, history, receipt lineage, trust base, policy pin, waivers, unclaimed witnesses)"
fi
exit 0
