#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# run-controls.sh — prove the proof-witness instrument works BOTH ways.
#
# metadatastician/standards 3-practice/PROOF-POLICY.adoc §7 requires a policy gate
# to be verified "both ways": it passes conforming input AND fails a deliberately
# planted violation. A gate that has only ever been seen to pass is
# indistinguishable from one that cannot fail.
#
# This script runs the verification in three parts:
#
#   1. run-ledger-controls.sh — 51 controls over RECORDED claims, MANIFEST status,
#      reconciliation vocabulary, and comment-aware lexical scanning (no prover
#      needed; runs everywhere).
#   2. K1–K5: direct kernel sanity checks (`coqc`/`coqtop`/`lean`) confirming
#      the installed toolchains distinguish closed proofs from `Admitted`/`sorry`.
#   3. K6–K15: end-to-end `scripts/check-proofs.sh` compiled-witness assumption
#      controls (nextgen-typing#131) exercising `coqchk -silent -o`, generated
#      `Print Assumptions` drivers, and generated Lean `#print axioms` probes
#      BOTH WAYS — clean witnesses, stdlib-imported axioms (`Classical_Prop.classic`,
#      `Classical.em`), cross-module helper `Axiom` and imported `sorryAx`,
#      `proven-with-postulates` pass/stale-axiom mismatch, missing declarations,
#      clean working-tree staging, and verbatim assumption receipts.
#
# Exit: 0 every control behaved as required; 1 an expectation was violated;
#       2 BLOCKED — a prover tool the controls need is not installed here.
#       BLOCKED is never reported as a pass (PROOF-POLICY §6).

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT" || exit 2

CONTROLS="tests/proofs/control"
CHECK_PROOFS="$ROOT/scripts/check-proofs.sh"
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

# --- 2. the kernel half: absent means BLOCKED, never a pass -----------------
echo "=== Kernel & compiled-witness assumption controls (need coqc, coqchk, coqtop, lean) ==="
missing=()
for tool in coqc coqchk coqtop lean jq; do
  command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done
if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "BLOCKED: the kernel controls need ${missing[*]} on PATH, and the instrument"
  echo "         cannot be shown to work without them. This is NOT a pass (PROOF-POLICY §6)."
  exit 2
fi
echo "coqc:   $(coqc --version 2>/dev/null | head -1)"
echo "coqchk: $(coqchk --version 2>&1 | head -1)"
echo "lean:   $(lean --version 2>/dev/null | head -1)"
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
lean_clean_rc=$?
if [[ "$lean_clean_rc" -eq 0 ]] && printf '%s' "$lean_clean" | grep -q "does not depend on any axioms"; then
  ok "K4. lean exits 0 and #print axioms reports the closed Lean control as axiom-free"
else
  viol "K4. lean exited $lean_clean_rc or #print axioms did not report the closed Lean control as axiom-free"
  printf '%s\n' "$lean_clean" | sed 's/^/      /' | head -20
fi

lean_planted="$( cd "$CONTROLS" && lean PlantedSorry.lean 2>&1 )"
if printf '%s' "$lean_planted" | grep -q "sorryAx"; then
  ok "K5. #print axioms exposes sorryAx in the planted Lean control"
else
  viol "K5. #print axioms did not expose sorryAx — Lean axiom tracking is blind"
  printf '%s\n' "$lean_planted" | sed 's/^/      /' | head -20
fi

# --- 3. end-to-end compiled-witness assumption controls (#131) --------------
write_fixture_ledger() {
  # $1=ledger_file $2=prover(rocq|lean4) $3=status $4=artifact $5=support_json $6=decls_json $7=axioms_json
  local lfile="$1" prover="$2" st="$3" art="$4" sup_json="$5" decls_json="$6" ax_json="$7"
  mkdir -p "$(dirname "$lfile")"
  jq -n \
    --arg prover "$prover" \
    --arg st "$st" \
    --arg art "$art" \
    --argjson sup "$sup_json" \
    --argjson decls "$decls_json" \
    --argjson ax "$ax_json" \
    '{
      schema: "hyperpolymath/proof-ledger/1",
      theorems: [
        {
          id: "CTRL-1",
          kind: "theory",
          grade: "2i",
          statement_formal: {
            declarations: [
              { name: "TP-ECHO-1", type: "True" }
            ]
          },
          legs: [
            {
              prover: $prover,
              family: "dtt",
              status: $st,
              route: "re-proved",
              reproof_reason: "instrument control",
              artifact: $art,
              support_files: $sup,
              declarations: $decls,
              axioms: $ax,
              statement_compared: "instrument control"
            }
          ]
        }
      ]
    }' > "$lfile"
}

# K6: Rocq clean witness passes check-proofs.sh coq, writes verbatim coqchk +
# Print Assumptions output to receipt, and leaves zero .vo/.glob in source tree.
k6="$WORK/k6"
mkdir -p "$k6/verification/proofs/coq"
cat > "$k6/verification/proofs/coq/CleanWitness.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Theorem tp_echo_1 : True. Proof. exact I. Qed.
Theorem tp_echo_2 : True. Proof. exact I. Qed.
EOF
printf 'verification/proofs/coq|CleanWitness.v|gated|clean witness\n' > "$k6/verification/proofs/coq/MANIFEST"
write_fixture_ledger "$k6/verification/proofs/LEDGER.json" "rocq" "proven" \
  "verification/proofs/coq/CleanWitness.v" "null" '["tp_echo_1","tp_echo_2"]' '[]'
if bash "$CHECK_PROOFS" coq --root "$k6" --receipt "$k6/receipt.txt" >"$k6/out.log" 2>&1 \
   && grep -qF "CONTEXT SUMMARY" "$k6/receipt.txt" \
   && grep -qF "Closed under the global context" "$k6/receipt.txt" \
   && [[ -z "$(find "$k6/verification/proofs/coq" \( -name '*.vo' -o -name '*.glob' \) 2>/dev/null)" ]]; then
  ok "K6. check-proofs.sh coq accepts a closed Rocq witness, writes verbatim coqchk + Print Assumptions receipt, and keeps worktree clean"
else
  viol "K6. check-proofs.sh coq failed on a closed Rocq witness or omitted verbatim receipt"
  sed 's/^/      /' "$k6/out.log" | tail -20
  [[ -f "$k6/receipt.txt" ]] && sed 's/^/      [receipt] /' "$k6/receipt.txt" | tail -25
fi

# K7: Rocq witness importing Classical_Prop.classic (lexically clean) is REFUSED when axioms: [].
k7="$WORK/k7"
mkdir -p "$k7/verification/proofs/coq"
cp "$CONTROLS/ControlImportedAxiom.v" "$k7/verification/proofs/coq/ControlImportedAxiom.v"
printf 'verification/proofs/coq|ControlImportedAxiom.v|gated|imported classic\n' > "$k7/verification/proofs/coq/MANIFEST"
write_fixture_ledger "$k7/verification/proofs/LEDGER.json" "rocq" "proven" \
  "verification/proofs/coq/ControlImportedAxiom.v" "null" '["imported_em"]' '[]'
if bash "$CHECK_PROOFS" coq --root "$k7" --receipt "$k7/receipt.txt" >"$k7/out.log" 2>&1; then
  viol "K7. check-proofs.sh coq ACCEPTED an undeclared imported stdlib axiom (Classical_Prop.classic)"
elif grep -qF "classic" "$k7/out.log"; then
  ok "K7. check-proofs.sh coq refuses an undeclared imported stdlib axiom (Classical_Prop.classic) that lexical scan cannot see"
else
  viol "K7. check-proofs.sh coq failed on imported stdlib axiom for the wrong reason"
  sed 's/^/      /' "$k7/out.log" | tail -20
fi

# K8: Same Rocq witness with proven-with-postulates naming Coq.Logic.Classical_Prop.classic PASSES.
k8="$WORK/k8"
mkdir -p "$k8/verification/proofs/coq"
cp "$CONTROLS/ControlImportedAxiom.v" "$k8/verification/proofs/coq/ControlImportedAxiom.v"
printf 'verification/proofs/coq|ControlImportedAxiom.v|gated|declared classic\n' > "$k8/verification/proofs/coq/MANIFEST"
write_fixture_ledger "$k8/verification/proofs/LEDGER.json" "rocq" "proven-with-postulates" \
  "verification/proofs/coq/ControlImportedAxiom.v" "null" '["imported_em"]' '["Coq.Logic.Classical_Prop.classic"]'
if bash "$CHECK_PROOFS" coq --root "$k8" --receipt "$k8/receipt.txt" >"$k8/out.log" 2>&1 \
   && grep -qF "Coq.Logic.Classical_Prop.classic" "$k8/receipt.txt"; then
  ok "K8. check-proofs.sh coq accepts proven-with-postulates when the imported Rocq axiom matches LEDGER.json and records it in receipt"
else
  viol "K8. check-proofs.sh coq rejected a properly declared Rocq axiom in proven-with-postulates"
  sed 's/^/      /' "$k8/out.log" | tail -20
  [[ -f "$k8/receipt.txt" ]] && sed 's/^/      [receipt] /' "$k8/receipt.txt" | tail -25
fi

# K9: Cross-module local helper Axiom imported by a clean surface witness is REFUSED when unrecorded.
k9="$WORK/k9"
mkdir -p "$k9/verification/proofs/coq"
cat > "$k9/verification/proofs/coq/HelperAx.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Axiom helper_ax : True.
EOF
cat > "$k9/verification/proofs/coq/SurfaceClean.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Require Import HelperAx.
Theorem tp_from_helper : True. Proof. exact helper_ax. Qed.
EOF
cat > "$k9/verification/proofs/coq/MANIFEST" <<'EOF'
verification/proofs/coq|HelperAx.v|gated|support module
verification/proofs/coq|SurfaceClean.v|gated|surface witness
EOF
write_fixture_ledger "$k9/verification/proofs/LEDGER.json" "rocq" "proven" \
  "verification/proofs/coq/SurfaceClean.v" '["verification/proofs/coq/HelperAx.v"]' '["tp_from_helper"]' '[]'
if bash "$CHECK_PROOFS" coq --root "$k9" >"$k9/out.log" 2>&1; then
  viol "K9. check-proofs.sh coq ACCEPTED a cross-module helper Axiom under axioms: []"
elif grep -qF "helper_ax" "$k9/out.log"; then
  ok "K9. check-proofs.sh coq refuses a cross-module helper Axiom imported into a clean surface witness"
else
  viol "K9. check-proofs.sh coq failed on cross-module helper Axiom for the wrong reason"
  sed 's/^/      /' "$k9/out.log" | tail -20
fi

# K10: Axiom-free Rocq witness missing a recorded target declaration is REFUSED by Print Assumptions probe.
k10="$WORK/k10"
mkdir -p "$k10/verification/proofs/coq"
cat > "$k10/verification/proofs/coq/PartialWitness.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Theorem tp_echo_1 : True. Proof. exact I. Qed.
EOF
printf 'verification/proofs/coq|PartialWitness.v|gated|partial witness\n' > "$k10/verification/proofs/coq/MANIFEST"
write_fixture_ledger "$k10/verification/proofs/LEDGER.json" "rocq" "proven" \
  "verification/proofs/coq/PartialWitness.v" "null" '["tp_echo_1","tp_echo_missing"]' '[]'
if bash "$CHECK_PROOFS" coq --root "$k10" >"$k10/out.log" 2>&1; then
  viol "K10. check-proofs.sh coq ACCEPTED a witness missing a recorded declaration"
elif grep -qF "Print Assumptions failed" "$k10/out.log"; then
  ok "K10. check-proofs.sh coq refuses an axiom-free witness that omits a recorded declaration"
else
  viol "K10. check-proofs.sh coq failed on missing declaration for the wrong reason"
  sed 's/^/      /' "$k10/out.log" | tail -20
fi

# K11: Lean clean witness passes check-proofs.sh lean4, writes verbatim #print axioms receipt,
# and leaves zero .olean files in the source tree.
k11="$WORK/k11"
mkdir -p "$k11/verification/proofs/lean4"
cat > "$k11/verification/proofs/lean4/CleanWitness.lean" <<'EOF'
-- INSTRUMENT CONTROL
theorem tp_echo_1 : True := True.intro
theorem tp_echo_2 : True := True.intro
EOF
printf 'verification/proofs/lean4|CleanWitness.lean|gated|clean witness\n' > "$k11/verification/proofs/lean4/MANIFEST"
write_fixture_ledger "$k11/verification/proofs/LEDGER.json" "lean4" "proven" \
  "verification/proofs/lean4/CleanWitness.lean" "null" '["tp_echo_1","tp_echo_2"]' '[]'
if bash "$CHECK_PROOFS" lean4 --root "$k11" --receipt "$k11/receipt.txt" >"$k11/out.log" 2>&1 \
   && grep -qF "does not depend on any axioms" "$k11/receipt.txt" \
   && [[ -z "$(find "$k11/verification/proofs/lean4" -name '*.olean' 2>/dev/null)" ]]; then
  ok "K11. check-proofs.sh lean4 accepts a closed Lean witness, writes verbatim #print axioms receipt, and keeps worktree clean"
else
  viol "K11. check-proofs.sh lean4 failed on a closed Lean witness or omitted verbatim receipt"
  sed 's/^/      /' "$k11/out.log" | tail -20
  [[ -f "$k11/receipt.txt" ]] && sed 's/^/      [receipt] /' "$k11/receipt.txt" | tail -25
fi

# K12: Lean witness using Classical.em (lexically clean) is REFUSED when axioms: [].
k12="$WORK/k12"
mkdir -p "$k12/verification/proofs/lean4"
cp "$CONTROLS/ControlImportedAxiom.lean" "$k12/verification/proofs/lean4/ControlImportedAxiom.lean"
printf 'verification/proofs/lean4|ControlImportedAxiom.lean|gated|imported classical\n' > "$k12/verification/proofs/lean4/MANIFEST"
write_fixture_ledger "$k12/verification/proofs/LEDGER.json" "lean4" "proven" \
  "verification/proofs/lean4/ControlImportedAxiom.lean" "null" '["imported_em"]' '[]'
if bash "$CHECK_PROOFS" lean4 --root "$k12" --receipt "$k12/receipt.txt" >"$k12/out.log" 2>&1; then
  viol "K12. check-proofs.sh lean4 ACCEPTED undeclared Classical.em axioms under axioms: []"
elif grep -qF "undeclared axiom" "$k12/out.log"; then
  ok "K12. check-proofs.sh lean4 refuses undeclared Classical.em axioms that lexical scan cannot see"
else
  viol "K12. check-proofs.sh lean4 failed on Classical.em for the wrong reason"
  sed 's/^/      /' "$k12/out.log" | tail -20
fi

# K13: Same Lean witness with proven-with-postulates naming propext, Classical.choice, Quot.sound PASSES.
k13="$WORK/k13"
mkdir -p "$k13/verification/proofs/lean4"
cp "$CONTROLS/ControlImportedAxiom.lean" "$k13/verification/proofs/lean4/ControlImportedAxiom.lean"
printf 'verification/proofs/lean4|ControlImportedAxiom.lean|gated|declared classical\n' > "$k13/verification/proofs/lean4/MANIFEST"
write_fixture_ledger "$k13/verification/proofs/LEDGER.json" "lean4" "proven-with-postulates" \
  "verification/proofs/lean4/ControlImportedAxiom.lean" "null" '["imported_em"]' '["propext","Classical.choice","Quot.sound"]'
if bash "$CHECK_PROOFS" lean4 --root "$k13" --receipt "$k13/receipt.txt" >"$k13/out.log" 2>&1 \
   && grep -qF "Classical.choice" "$k13/receipt.txt"; then
  ok "K13. check-proofs.sh lean4 accepts proven-with-postulates when all Lean axioms match LEDGER.json and records them in receipt"
else
  viol "K13. check-proofs.sh lean4 rejected a properly declared Lean axiom set in proven-with-postulates"
  sed 's/^/      /' "$k13/out.log" | tail -20
  [[ -f "$k13/receipt.txt" ]] && sed 's/^/      [receipt] /' "$k13/receipt.txt" | tail -25
fi

# K14: Cross-module imported sorry (sorryAx) is REFUSED both when axioms: [] and when axioms: ["sorryAx"].
k14="$WORK/k14"
mkdir -p "$k14/verification/proofs/lean4"
cat > "$k14/verification/proofs/lean4/HelperSorry.lean" <<'EOF'
-- INSTRUMENT CONTROL
theorem helper_hole : False := sorry
EOF
cat > "$k14/verification/proofs/lean4/SurfaceViaHole.lean" <<'EOF'
-- INSTRUMENT CONTROL
import HelperSorry
theorem surface_claim : False := helper_hole
EOF
cat > "$k14/verification/proofs/lean4/MANIFEST" <<'EOF'
verification/proofs/lean4|HelperSorry.lean|gated|helper with sorry
verification/proofs/lean4|SurfaceViaHole.lean|gated|clean-looking surface
EOF
write_fixture_ledger "$k14/verification/proofs/LEDGER.json" "lean4" "proven" \
  "verification/proofs/lean4/SurfaceViaHole.lean" '["verification/proofs/lean4/HelperSorry.lean"]' '["surface_claim"]' '[]'
bash "$CHECK_PROOFS" lean4 --root "$k14" >"$k14/out-empty.log" 2>&1
rc_empty=$?
write_fixture_ledger "$k14/verification/proofs/LEDGER.json" "lean4" "proven-with-postulates" \
  "verification/proofs/lean4/SurfaceViaHole.lean" '["verification/proofs/lean4/HelperSorry.lean"]' '["surface_claim"]' '["sorryAx"]'
bash "$CHECK_PROOFS" lean4 --root "$k14" >"$k14/out-listed.log" 2>&1
rc_listed=$?
if [[ "$rc_empty" -ne 0 && "$rc_listed" -ne 0 ]] \
   && grep -qF "sorryAx" "$k14/out-empty.log" \
   && grep -qF "sorryAx" "$k14/out-listed.log"; then
  ok "K14. check-proofs.sh lean4 refuses cross-module imported sorryAx whether unrecorded or listed in .axioms"
else
  viol "K14. check-proofs.sh lean4 did not refuse cross-module sorryAx in both modes (rc_empty=$rc_empty, rc_listed=$rc_listed)"
  sed 's/^/      /' "$k14/out-empty.log" "$k14/out-listed.log" | tail -20
fi

# K15: Stale/padded axioms in .axioms on an actually closed witness are REFUSED in both Rocq and Lean.
k15="$WORK/k15"
mkdir -p "$k15/coq/verification/proofs/coq" "$k15/lean/verification/proofs/lean4"
printf '(* INSTRUMENT CONTROL *)\nTheorem tp_echo_1 : True. Proof. exact I. Qed.\n' > "$k15/coq/verification/proofs/coq/Clean.v"
printf 'verification/proofs/coq|Clean.v|gated|clean\n' > "$k15/coq/verification/proofs/coq/MANIFEST"
write_fixture_ledger "$k15/coq/verification/proofs/LEDGER.json" "rocq" "proven-with-postulates" \
  "verification/proofs/coq/Clean.v" "null" '["tp_echo_1"]' '["Coq.Logic.Classical_Prop.classic"]'
bash "$CHECK_PROOFS" coq --root "$k15/coq" >"$k15/coq.log" 2>&1
rc_coq_stale=$?

printf -- '-- INSTRUMENT CONTROL\ntheorem tp_echo_1 : True := True.intro\n' > "$k15/lean/verification/proofs/lean4/Clean.lean"
printf 'verification/proofs/lean4|Clean.lean|gated|clean\n' > "$k15/lean/verification/proofs/lean4/MANIFEST"
write_fixture_ledger "$k15/lean/verification/proofs/LEDGER.json" "lean4" "proven-with-postulates" \
  "verification/proofs/lean4/Clean.lean" "null" '["tp_echo_1"]' '["propext"]'
bash "$CHECK_PROOFS" lean4 --root "$k15/lean" >"$k15/lean.log" 2>&1
rc_lean_stale=$?

if [[ "$rc_coq_stale" -ne 0 && "$rc_lean_stale" -ne 0 ]] \
   && grep -qF "stale axioms" "$k15/coq.log" \
   && grep -qF "stale axioms" "$k15/lean.log"; then
  ok "K15. check-proofs.sh refuses stale/padded .axioms entries on closed witnesses in both Rocq and Lean"
else
  viol "K15. check-proofs.sh accepted stale/padded .axioms entries (coq=$rc_coq_stale, lean=$rc_lean_stale)"
  sed 's/^/      /' "$k15/coq.log" "$k15/lean.log" | tail -20
fi

# K16: An incomplete Rocq proof closed with `Admitted.` is REFUSED by the kernel
# check even when its full qualified name (`AdmittedWitness.tp_echo_1`) is listed
# in `legs[].axioms` under `proven-with-postulates` (matching Lean's sorryAx ban).
k16="$WORK/k16"
mkdir -p "$k16/verification/proofs/coq"
cat > "$k16/verification/proofs/coq/AdmittedWitness.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Theorem tp_echo_1 : False.
Proof. Admitted.
EOF
cat > "$k16/verification/proofs/coq/MANIFEST" <<'EOF'
verification/proofs/coq|AdmittedWitness.v|gated|admitted control
EOF
write_fixture_ledger "$k16/verification/proofs/LEDGER.json" "rocq" "proven-with-postulates" \
  "verification/proofs/coq/AdmittedWitness.v" "null" '["tp_echo_1"]' '["AdmittedWitness.tp_echo_1"]'
bash "$CHECK_PROOFS" coq --root "$k16" >"$k16/out.log" 2>&1
rc_k16=$?
if [[ "$rc_k16" -ne 0 ]] && grep -qF "FAIL (assumptions)" "$k16/out.log"; then
  ok "K16. check-proofs.sh coq refuses an Admitted theorem even when its full qualified name is listed in .axioms"
else
  viol "K16. check-proofs.sh coq accepted an Admitted theorem listed in .axioms (rc=$rc_k16)"
  sed 's/^/      /' "$k16/out.log" | tail -20
fi

# K17: Multi-file MANIFEST out of dependency order (importer listed before its
# support_files module) is REFUSED with a manifest-order diagnostic.
k17="$WORK/k17"
mkdir -p "$k17/verification/proofs/coq"
cat > "$k17/verification/proofs/coq/HelperClean.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Theorem helper_true : True. Proof. exact I. Qed.
EOF
cat > "$k17/verification/proofs/coq/SurfaceFirst.v" <<'EOF'
(* INSTRUMENT CONTROL *)
Require Import HelperClean.
Theorem surface_true : True. Proof. exact helper_true. Qed.
EOF
cat > "$k17/verification/proofs/coq/MANIFEST" <<'EOF'
verification/proofs/coq|SurfaceFirst.v|gated|importer listed too early
verification/proofs/coq|HelperClean.v|gated|support module listed too late
EOF
write_fixture_ledger "$k17/verification/proofs/LEDGER.json" "rocq" "proven" \
  "verification/proofs/coq/SurfaceFirst.v" '["verification/proofs/coq/HelperClean.v"]' '["surface_true"]' '[]'
bash "$CHECK_PROOFS" coq --root "$k17" >"$k17/out.log" 2>&1
rc_k17=$?
if [[ "$rc_k17" -ne 0 ]] && grep -qF "FAIL (manifest-order)" "$k17/out.log"; then
  ok "K17. check-proofs.sh refuses a multi-file MANIFEST listing an importer before its support_files module"
else
  viol "K17. check-proofs.sh did not diagnose out-of-order support_files in MANIFEST (rc=$rc_k17)"
  sed 's/^/      /' "$k17/out.log" | tail -20
fi

echo ""
if [[ "$VIOLATIONS" -gt 0 ]]; then
  echo "FAIL: $VIOLATIONS control expectation(s) violated — the instrument does not behave as"
  echo "      claimed, so a green proof lane would mean nothing."
  exit 1
fi
echo "PASS: every control behaved as required — the instrument passes what should pass"
echo "      and fails what must fail ($CHECKS kernel & witness expectation(s); the"
echo "      ledger-form controls reported their own count above)."
if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
  echo "::notice::proof-witness kernel & assumption controls verified both ways (§7, #131): $CHECKS expectation(s), 0 violations, coqc $(coqc --version | head -1), lean $(lean --version | head -1)"
fi
exit 0
