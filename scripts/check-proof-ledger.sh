#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-proof-ledger.sh — proof-LEDGER gate for nextgen-typing.
#
# What this refuses to do, and why:
#
#   * It does NOT re-run the Agda theory proof. Under
#     metadatastician/standards 3-practice/PROOF-POLICY.adoc §1 a theory proof's source of
#     truth is Agda and its §2 recheck legs are Rocq and Lean. Those legs are
#     what this repository's proof CI examines (Coq/Rocq and Lean 4 only).
#     The Agda leg is *recorded* — with the commit and run that checked it —
#     and audited for form here, not re-derived.
#   * It does NOT accept a grade the evidence does not support. mathesis
#     `estate-mathematical-architecture` §5/§6 defines Grade 3 (Agda only,
#     not translated) through Grade 1 (machine-checked through a verified
#     checker API), and §6 requires exact recording rather than a confidence
#     percentage. A ledger that claims a travelled leg must have the artifact,
#     the manifest entry, the route, the statement comparison and the axiom
#     list behind it, or this gate fails.
#   * It does NOT report a clean run when there was nothing to audit: zero
#     theorems, a theorem with no source file, or a theory theorem with no
#     recheck legs listed are failures, not passes.
#
# An `open` leg is a LEGAL status (PROOF-POLICY §5). When a leg is open this
# gate prints a POLICY GAP line naming the leg and the policy clause it owes,
# and nothing in the output claims that the theorem is verified.
#
# Usage:
#   bash scripts/check-proof-ledger.sh [--ledger PATH] [--receipt PATH]
#   bash scripts/check-proof-ledger.sh --scan-file PATH   # both-ways control
#
# Exit: 0 = PASS (every claim is backed, every open leg recorded)
#       1 = FAIL (a claim is unsupported, or bookkeeping does not add up)
#       2 = BLOCKED (gate could not audit: jq/git/policy input unavailable)

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

LEDGER="verification/proofs/LEDGER.json"
RECEIPT=""
SCAN_FILE=""
PROOFS_DIR="verification/proofs"
MANIFEST_SOURCE=".machine_readable/bot_directives/placement.a2ml"
BOUNDARY_SCRIPT="scripts/check-coordination-boundary.sh"
DOCS_STATUS="PROOF-STATUS.adoc"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --ledger) LEDGER="${2:-}"; shift 2 ;;
    --ledger=*) LEDGER="${1#--ledger=}"; shift ;;
    --receipt) RECEIPT="${2:-}"; shift 2 ;;
    --receipt=*) RECEIPT="${1#--receipt=}"; shift ;;
    --scan-file) SCAN_FILE="${2:-}"; shift 2 ;;
    --scan-file=*) SCAN_FILE="${1#--scan-file=}"; shift ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

FAILS=()
NOTES=()
GAPS=()
WAIVERS=()
fail() { FAILS+=("$1"); }
note() { NOTES+=("$1"); }

# ---------------------------------------------------------------------------
# Escape-hatch scan (shared by the repo audit and the both-ways control).
# Comment-aware: PROOF-POLICY keeps escape-hatch *policy* in
# docs/TRUSTED-BASE-REDUCTION-POLICY.adoc, and a prose mention of a banned
# construct is not a hole. The delegated scanner strips comments according to
# the file's language and preserves line numbers.
# ---------------------------------------------------------------------------
scan_escape_hatches() {
  # $1 = file. Prints numbered matching lines; scanner errors become a
  # synthetic line 0 hit, so callers treat them as failures.
  #
  # ONE pattern list, not two. This function used to carry its own copy, which
  # drifted: it knew `believe_me|assert_total|postulate|sorry|admit|Admitted|
  # unsafeCoerce` and missed the rest of the estate policy's CORE tier (Coq
  # `Axiom`, Lean `axiom`, Idris2 `really_believe_me`/`partial`, F* `assume val`,
  # `unsafePerformIO`). The scanner owns the list; this delegates so a marker
  # can never be caught by one gate and missed by the other.
  local file="$1"
  local out rc
  out="$(bash "$ROOT/scripts/proof-scan-dangerous.sh" --scan-file "$file" 2>&1)"; rc=$?
  if [ "$rc" -gt 1 ]; then
    printf '0:scanner-error:proof-scan-dangerous.sh exited %s for %s\n' "$rc" "$file"
    return 0
  fi
  printf '%s\n' "$out" | sed -n 's/^\([0-9][0-9]*\):/\1:/p'
}

# Declared axioms are different from escape hatches: PROOF-POLICY §5 allows
# `proven-with-postulates` when the axioms are named and allowed by
# TRUSTED-BASE-REDUCTION-POLICY. Strip comments first so prose in comments
# (e.g. `(* Axiom fake : False. *)`) can never impersonate a declared axiom.
scan_declared_axioms() {
  local file="$1"
  case "$file" in
    *.v)
      bash "$ROOT/scripts/proof-scan-dangerous.sh" --strip-comments "$file" \
        | grep -nE '^[[:space:]]*(Axiom|Parameter|Conjecture)[[:space:]]' || true
      ;;
    *.lean)
      bash "$ROOT/scripts/proof-scan-dangerous.sh" --strip-comments "$file" \
        | grep -nE '^[[:space:]]*axiom[[:space:]]' || true
      ;;
    *) true ;;
  esac
}

# ---------------------------------------------------------------------------
# --scan-file mode: the instrument's own control surface (PROOF-POLICY §7 —
# a gate must be shown to pass conforming input AND fail a planted violation).
# ---------------------------------------------------------------------------
if [ -n "$SCAN_FILE" ]; then
  if [ ! -f "$SCAN_FILE" ]; then
    echo "BLOCKED: --scan-file target does not exist: $SCAN_FILE" >&2
    exit 2
  fi
  hits="$(scan_escape_hatches "$SCAN_FILE")"
  if [ -n "$hits" ]; then
    echo "FAIL: escape hatches in $SCAN_FILE"
    echo "$hits" | sed 's/^/  line /'
    exit 1
  fi
  echo "PASS: no escape hatches in $SCAN_FILE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Inputs. A gate that cannot read its inputs must say so; it must not pass.
# ---------------------------------------------------------------------------
command -v jq >/dev/null 2>&1 || { echo "BLOCKED: jq is required to audit the ledger" >&2; exit 2; }

[ -f "$LEDGER" ] || { echo "BLOCKED: proof ledger not found: $LEDGER" >&2; exit 2; }
jq -e . "$LEDGER" >/dev/null 2>&1 || { echo "BLOCKED: proof ledger is not valid JSON: $LEDGER" >&2; exit 2; }

# The authority this audit is against. It is read out of the ledger rather than
# hard-coded: the policy lives in another repository, so a bare path here would
# be a citation to a file this tree does not contain.
POLICY_REPO="$(jq -r '.policy.proof_policy.repo // ""' "$LEDGER")"
POLICY_PATH="$(jq -r '.policy.proof_policy.path // ""' "$LEDGER")"
POLICY_COMMIT="$(jq -r '.policy.proof_policy.commit // ""' "$LEDGER")"
POLICY_RULING="$(jq -r '.policy.proof_policy.ruling // ""' "$LEDGER")"
POLICY_AMENDED="$(jq -r '.policy.proof_policy.amended // ""' "$LEDGER")"
POLICY_VENDORED="$(jq -r '.policy.proof_policy.vendored_here // false | tostring' "$LEDGER")"

policy_label() {
  if [ -n "$POLICY_REPO" ] && [ -n "$POLICY_PATH" ]; then
    printf '%s %s' "$POLICY_REPO" "$POLICY_PATH"
  else
    printf '%s' "${POLICY_PATH:-<unpinned>}"
  fi
}

echo "=== Proof ledger gate ==="
echo "ledger:   $LEDGER"
echo "policy:   $(policy_label)${POLICY_COMMIT:+ @ ${POLICY_COMMIT:0:12}}${POLICY_RULING:+ (${POLICY_RULING})}${POLICY_AMENDED:+, amended ${POLICY_AMENDED}}"
if [ "$POLICY_VENDORED" = "true" ]; then
  echo "          vendored copy in this tree"
else
  echo "          referenced, not vendored: this repository carries no copy of the policy"
fi
echo "grades:   mathesis/estate-mathematical-architecture §5-§6"
echo ""

# --- 1b. the authority must be pinned, not merely named ----------------------
if [ -z "$POLICY_REPO" ] || [ -z "$POLICY_PATH" ] || [ -z "$POLICY_RULING" ]; then
  fail "policy: the ledger's .policy.proof_policy must name the repository, the path and the ruling it was decided by (got repo='${POLICY_REPO}', path='${POLICY_PATH}', ruling='${POLICY_RULING}')"
fi
if ! printf '%s' "$POLICY_COMMIT" | grep -qE '^[0-9a-f]{40}$'; then
  fail "policy: .policy.proof_policy.commit must be the full 40-character commit the policy was read at (got '${POLICY_COMMIT}') — an unpinned policy is an unspecified obligation"
fi
if [ "$POLICY_VENDORED" = "true" ]; then
  [ -f "$POLICY_PATH" ] \
    || fail "policy: vendored_here is true but there is no file at '$POLICY_PATH' in this tree"
else
  if [ -f "$POLICY_PATH" ]; then
    note "policy: '$POLICY_PATH' exists in this tree but is recorded as not vendored — reconcile the two"
  fi
fi

# Closed vocabulary, verbatim from PROOF-POLICY §5 (canonical lowercase tokens).
VOCAB='["argued","open","proven","proven-with-postulates","tested-only"]'
# Prover families, from mathesis §5 (the Grade 2ii diversity rule).
FAMILIES='{"agda":"dtt","rocq":"dtt","lean4":"dtt","idris2":"dtt","isabelle":"hol","tla+":"state-machine","smt":"smt"}'

# Print the 1-based entry index if the manifest has a gated entry for the target
# path; return 1 if the manifest is missing or has no such entry.
manifest_gated_index() {
  local mfile="$1" target="$2"
  [[ -f "$mfile" ]] || return 1
  awk -F'|' -v want="$target" '
    /^[[:space:]]*(#|$)/ { next }
    NF >= 3 {
      idx++
      r = $1; sub(/^[[:space:]]+/, "", r); sub(/[[:space:]]+$/, "", r); sub(/\/+$/, "", r); sub(/^\.\//, "", r)
      m = $2; sub(/^[[:space:]]+/, "", m); sub(/[[:space:]]+$/, "", m); sub(/^\.\//, "", m)
      s = $3; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s)
      full = (r == "" || r == ".") ? m : (r "/" m)
      if (full == want && s == "gated") { print idx; found = 1; exit }
    }
    END { exit (found ? 0 : 1) }
  ' "$mfile"
}

# Return success if the manifest has a gated entry for the target path;
# return 1 if the manifest is missing or a readable manifest has no such entry.
manifest_is_gated() {
  manifest_gated_index "$1" "$2" >/dev/null
}

is_valid_target_ident() {
  local ident="$1"
  [[ "$ident" =~ ^[A-Za-z_][A-Za-z0-9_\']*(\.[A-Za-z_][A-Za-z0-9_\']*)*$ ]]
}

# --- 1. schema + non-empty ---------------------------------------------------
schema="$(jq -r '.schema // ""' "$LEDGER")"
[ "$schema" = "hyperpolymath/proof-ledger/1" ] \
  || fail "schema: expected 'hyperpolymath/proof-ledger/1', got '${schema}'"

theorem_count="$(jq -r '.theorems | if type=="array" then length else -1 end' "$LEDGER")"
if [ "$theorem_count" -le 0 ]; then
  fail "zero-work: the ledger must declare at least one theorem (it declares ${theorem_count})"
fi

# --- 2. closed vocabulary, kinds, ids, grades --------------------------------
while IFS= read -r bad; do
  [ -n "$bad" ] && fail "status token outside PROOF-POLICY §5 vocabulary: '${bad}'"
done < <(jq -r --argjson vocab "$VOCAB" '
  [ .theorems[] | (.source.status // "<missing>"),
                  (.legs[]? | select(.waiver == null) | (.status // "<missing>")) ][]
  | select(. as $s | $vocab | index($s) | not)' "$LEDGER" | sort -u)

while IFS= read -r bad; do
  [ -n "$bad" ] && fail "theorem kind must be 'theory' or 'engineering' (PROOF-POLICY §1): '${bad}'"
done < <(jq -r '[.theorems[].kind // "<missing>"][] | select(. != "theory" and . != "engineering")' "$LEDGER" | sort -u)

if jq -e '.theorems[] | select((.id | type) != "string" or ((.id | gsub("^[[:space:]]+|[[:space:]]+$"; "")) == "") or (.id | test("[[:space:]]")))' "$LEDGER" >/dev/null 2>&1; then
  fail "theorem id: every theorem in .theorems[] must carry a non-empty, whitespace-free string .id"
fi

while IFS= read -r shape_err; do
  [ -n "$shape_err" ] && fail "malformed theorem entry: $shape_err"
done < <(jq -r '
  .theorems[] | (if (.id | type) == "string" and (.id | length) > 0 then .id else "<unnamed>" end) as $id |
  [
    (if (.source | type) != "object" then "\($id): .source must be an object" else empty end),
    (if ((.source | type) == "object" and (.source.files != null) and ((.source.files | type) != "array")) then "\($id): .source.files must be an array" else empty end),
    (if ((.source | type) == "object" and (.source.safety_flags != null) and ((.source.safety_flags | type) != "array")) then "\($id): .source.safety_flags must be an array" else empty end),
    (if ((.source | type) == "object" and (.source.flags_provenance != null) and ((.source.flags_provenance | type) != "object")) then "\($id): .source.flags_provenance must be an object" else empty end),
    (if (.statement_anchor != null and (.statement_anchor | type) != "array") then "\($id): .statement_anchor must be an array" else empty end),
    (if (.statement_formal != null and (.statement_formal | type) != "object") then "\($id): .statement_formal must be an object" else empty end),
    (if (.legs != null and (.legs | type) != "array") then "\($id): .legs must be an array" else empty end),
    (if (.history | type) != "array" then "\($id): .history must be an array (mathesis §6)"
     elif (.history | length) == 0 then "\($id): .history must record at least one baseline or transition entry (mathesis §6)"
     else empty end),
    (if (.caveats != null and (.caveats | type) != "array") then "\($id): .caveats must be an array" else empty end)
  ][]' "$LEDGER")

while IFS= read -r dup; do
  [ -n "$dup" ] && fail "duplicate theorem id in ledger: '${dup}'"
done < <(jq -r '[.theorems[].id] | group_by(.)[] | select(length > 1) | .[0]' "$LEDGER")

while IFS= read -r bad; do
  [ -n "$bad" ] && fail "grade must be one of 3, 2i, 2ii, 1 (mathesis §5): '${bad}'"
done < <(jq -r '[.theorems[].grade // "<missing>" | tostring][] | select(. != "3" and . != "2i" and . != "2ii" and . != "1")' "$LEDGER" | sort -u)

# --- 3. per-theorem: legs, grades, claims ------------------------------------
# Emitted as TSV so bash can drive the filesystem checks. Independent recheck
# counts exclude `.source.prover`, so duplicating the source prover as a leg
# cannot inflate Grade 3 to Grade 2i.
ROWS_TSV="$(mktemp)" || { echo "BLOCKED: cannot create a temporary file" >&2; exit 2; }
trap 'rm -f "$ROWS_TSV"' EXIT
if ! jq -r '
  .theorems[] as $t |
  (if ($t.source | type) == "object" then ($t.source.prover // "") else "" end) as $src |
  [ ($t.id | tostring),
    ($t.kind // ""),
    ($t.grade | tostring),
    ([ (if ($t.legs | type) == "array" then $t.legs[] else empty end) | .prover // "" ] | join(",")),
    ([ (if ($t.legs | type) == "array" then $t.legs[] else empty end) | select(.waiver == null) | select(.status != "open") ] | length),
    ([ (if ($t.legs | type) == "array" then $t.legs[] else empty end) | select(.waiver == null)
       | select((.prover // "") != $src)
       | select(.status == "proven" or .status == "proven-with-postulates") ] | length)
  ] | map(tostring) | join("\u001f")' "$LEDGER" > "$ROWS_TSV" 2>/dev/null; then
  fail "ledger shape error: unable to extract per-theorem rows via jq"
fi

declare -A THEOREM_PROVEN=()
while IFS=$'\x1f' read -r tid kind grade provers claimed proven; do
  [[ -z "$tid" ]] && continue
  THEOREM_PROVEN["$tid"]="$proven"

  # PROOF-POLICY §1/§2: theory is Agda, rechecked in Rocq AND Lean.
  if [[ "$kind" == "theory" ]]; then
    for required in rocq lean4; do
      case ",$provers," in
        *",$required,"*) ;;
        *) fail "$tid: theory theorem is missing the '$required' recheck leg required by PROOF-POLICY §2 (legs: ${provers:-none})" ;;
      esac
    done
  fi

  case "$grade" in
    3)
      if [[ "$proven" -gt 0 ]]; then
        fail "$tid: grade 3 claims no translated leg, but $proven leg(s) are recorded proven (mathesis §5)"
      fi
      ;;
    2i)
      # mathesis §5: Grade 2i applies when >=1 independent recheck leg is proven
      # within the DTT family (including when both PROOF-POLICY §2 DTT legs —
      # rocq + lean4 — are proven, before a non-DTT leg promotes the theorem to 2ii).
      if [[ "$proven" -lt 1 ]]; then
        fail "$tid: grade 2i requires at least one independent proven recheck leg, ledger records $proven (mathesis §5)"
      fi
      ;;
    2ii)
      if [[ "$proven" -lt 2 ]]; then
        fail "$tid: grade 2ii requires two proven legs, ledger records $proven (mathesis §5)"
      fi
      non_dtt="$(jq -r --argjson fam "$FAMILIES" --arg id "$tid" '
        .theorems[] | select(.id == $id) as $t
        | [ $t.legs[]?
            | select(.waiver == null)
            | select((.prover // "") != ($t.source.prover // ""))
            | select(.status == "proven" or .status == "proven-with-postulates")
            | select($fam[.prover // ""] != null and $fam[.prover] != "dtt") ] | length' "$LEDGER")"
      if [[ "${non_dtt:-0}" -lt 1 ]]; then
        fail "$tid: grade 2ii needs one proven leg outside the DTT/CIC family (mathesis §5 — Agda, Rocq and Lean are the same family); none recorded"
      fi
      ;;
    1)
      valid_api="$(jq -r --arg id "$tid" '
        [ .theorems[] | select(.id == $id) | .legs[]?
          | select(.waiver == null)
          | select(.status == "proven" or .status == "proven-with-postulates")
          | .api_receipt? | select(type == "object")
          | select((.api // "") == "axle" or (.api // "") == "coq-lsp" or (.api // "") == "isabelle-server")
          | select((.commit // "") | test("^[0-9a-f]{40}$"))
          | select(((.run // "") | gsub("\\s+"; "")) != "")
        ] | length' "$LEDGER")"
      if [[ "${valid_api:-0}" -lt 1 ]]; then
        fail "$tid: grade 1 requires a verified-checker API receipt (axle, coq-lsp, or isabelle-server with 40-char commit and run — mathesis §5); none recorded"
      fi
      ;;
  esac

  if [[ "$claimed" -gt 0 ]]; then
    NOTES+=("$tid: $claimed non-open recheck leg(s) recorded — compiled and kernel-queried by scripts/check-proofs.sh")
  fi
done < "$ROWS_TSV"

# --- 3a. cross-prover reconciliation status (mathesis CROSS-PROVER-RECONCILIATION)
# Never collapse distinct dimensions of verification: source Agda status, target
# Rocq/Lean kernel status, and bridge correspondence justification remain distinct.
while IFS=$'\x1f' read -r tid ragda rrocq rlean rbridge sstatus rocq_st lean_st uncomp_cnt; do
  [[ -z "$tid" ]] && continue
  case "$ragda" in
    ""|NOT-INVENTORIED|INVENTORIED|AGDA-PENDING|AGDA-VERIFIED|COUNTEREXAMPLE|QUARANTINED) ;;
    *) fail "$tid: reconciliation.agda '${ragda}' is outside mathesis CROSS-PROVER-RECONCILIATION vocabulary" ;;
  esac
  case "$rrocq" in
    ""|NOT-INVENTORIED|INVENTORIED|COQ-CHECKED|COUNTEREXAMPLE|QUARANTINED) ;;
    *) fail "$tid: reconciliation.rocq '${rrocq}' is outside mathesis CROSS-PROVER-RECONCILIATION vocabulary" ;;
  esac
  case "$rlean" in
    ""|NOT-INVENTORIED|INVENTORIED|LEAN-CHECKED|COUNTEREXAMPLE|QUARANTINED) ;;
    *) fail "$tid: reconciliation.lean4 '${rlean}' is outside mathesis CROSS-PROVER-RECONCILIATION vocabulary" ;;
  esac
  case "$rbridge" in
    ""|BRIDGE-PENDING|RECONCILED|COUNTEREXAMPLE|QUARANTINED) ;;
    *) fail "$tid: reconciliation.bridge '${rbridge}' is outside mathesis CROSS-PROVER-RECONCILIATION vocabulary" ;;
  esac
  if [[ "$ragda" == "AGDA-VERIFIED" && "$sstatus" != "proven" && "$sstatus" != "proven-with-postulates" ]]; then
    fail "$tid: reconciliation.agda claims 'AGDA-VERIFIED' while source.status is '$sstatus'"
  fi
  if [[ "$rrocq" == "COQ-CHECKED" && "$rocq_st" != "proven" && "$rocq_st" != "proven-with-postulates" ]]; then
    fail "$tid: reconciliation.rocq claims 'COQ-CHECKED' while the rocq leg is '${rocq_st:-missing}'"
  fi
  if [[ "$rlean" == "LEAN-CHECKED" && "$lean_st" != "proven" && "$lean_st" != "proven-with-postulates" ]]; then
    fail "$tid: reconciliation.lean4 claims 'LEAN-CHECKED' while the lean4 leg is '${lean_st:-missing}'"
  fi
  if [[ "$rbridge" == "RECONCILED" ]]; then
    if [[ "$rocq_st" != "proven" && "$rocq_st" != "proven-with-postulates" ]] \
       || [[ "$lean_st" != "proven" && "$lean_st" != "proven-with-postulates" ]] \
       || [[ "${uncomp_cnt:-0}" -gt 0 ]]; then
      fail "$tid: reconciliation.bridge claims 'RECONCILED', which requires independently verified Rocq and Lean targets plus justified statement comparisons (mathesis CROSS-PROVER-RECONCILIATION)"
    fi
  fi
done < <(jq -r '
  .theorems[] | select(.reconciliation != null) |
  . as $t |
  ([ $t.legs[]? | select(.prover == "rocq") | .status // "open" ][0] // "missing") as $rocq_st |
  ([ $t.legs[]? | select(.prover == "lean4") | .status // "open" ][0] // "missing") as $lean_st |
  ([ $t.legs[]? | select(.prover == "rocq" or .prover == "lean4")
     | select((.statement_compared // "") == "" or (.statement_compared | tostring) == "false") ] | length) as $uncomp |
  [ $t.id,
    ($t.reconciliation.agda // ""),
    ($t.reconciliation.rocq // ""),
    ($t.reconciliation.lean4 // ""),
    ($t.reconciliation.bridge // ""),
    ($t.source.status // ""),
    $rocq_st,
    $lean_st,
    ($uncomp | tostring)
  ] | join("\u001f")' "$LEDGER")

# --- 3b. the SOURCE leg must be substantiated, and its flags must be the ones
# actually in force -----------------------------------------------------------
# A Grade 3 claim is "Agda alone, and safe". That is only meaningful if (a) the
# source leg really is proven, (b) the flags recorded are the flags the lane
# really passes, and (c) the named declarations the statement rests on exist.
# None of this is taken on trust: the CLI flags are read out of the instrument
# (scripts/check-proofs.sh), the {-# OPTIONS #-} out of the proof files, and the
# identifiers out of the file named as the anchor.
AGDA_CLI_FLAGS="$(
  grep -oE 'agda --safe[^"]*' scripts/check-proofs.sh 2>/dev/null | head -1 \
    | grep -oE -- '--[a-zA-Z][a-zA-Z0-9-]*' | sort -u | tr '\n' ' ' | sed 's/ *$//'
)"
if [ -z "$AGDA_CLI_FLAGS" ]; then
  fail "could not read the Agda CLI flags out of scripts/check-proofs.sh (instrument changed shape) — the recorded flags cannot be cross-checked"
fi

file_agda_options() {  # $1.. = agda files; prints the sorted union of OPTIONS flags
  local f
  for f in "$@"; do
    [ -f "$f" ] || continue
    awk '/OPTIONS/ { rest = $0
                    while (match(rest, /--[a-zA-Z][a-zA-Z0-9-]*/)) {
                      print substr(rest, RSTART, RLENGTH)
                      rest = substr(rest, RSTART + RLENGTH)
                    } }' "$f"
  done | sort -u | tr '\n' ' ' | sed 's/ *$//'
}

while IFS=$'\x1f' read -r tid sprover sstatus rec_file_opts rec_cli rec_effective files_csv anchor_ids escape_evidence; do
  [ -z "$tid" ] && continue
  kind_of="$(
    jq -r --arg id "$tid" '.theorems[] | select(.id == $id) | .kind' "$LEDGER"
  )"

  # (a) PROOF-POLICY §1: a theory theorem's source of truth is Agda, and it
  # must actually be proven — a grade resting on an open source leg is a guess.
  if [ "$kind_of" = "theory" ] && [ "$sprover" != "agda" ]; then
    fail "$tid: a theory theorem's source leg must be Agda (PROOF-POLICY §1); ledger records '${sprover:-<missing>}'"
  fi
  case "$sstatus" in
    proven|proven-with-postulates) ;;
    *) fail "$tid: source leg status is '${sstatus:-<missing>}' — a recorded grade rests on the source of truth being proven, not asserted (PROOF-POLICY §5)" ;;
  esac

  # (b) .source.files must be a non-empty array of strings, every file must exist,
  # and for a proven source leg its files must be gated in the prover's MANIFEST.
  src_files_valid="$(jq -r --arg id "$tid" '
    .theorems[] | select(.id == $id) | .source.files
    | (type == "array" and length > 0 and all(.[]; type == "string" and length > 0)) | tostring' "$LEDGER")"
  if [[ "$src_files_valid" != "true" ]]; then
    fail "$tid: .source.files must be a non-empty JSON array of file paths"
    continue
  fi
  src_mdir=""
  case "$sprover" in
    agda) src_mdir="$PROOFS_DIR/agda" ;;
    rocq|coq) src_mdir="$PROOFS_DIR/coq" ;;
    lean4|lean) src_mdir="$PROOFS_DIR/lean4" ;;
    idris2) src_mdir="$PROOFS_DIR/idris2" ;;
    *)
      fail "$tid: unsupported .source.prover '${sprover:-<missing>}' — must be one of agda, idris2, rocq, lean4 (PROOF-POLICY §1)"
      continue
      ;;
  esac
  IFS=',' read -r -a src_files <<< "$files_csv"
  for f in "${src_files[@]}"; do
    [[ -z "$f" ]] && continue
    if [[ ! -f "$f" ]]; then
      fail "$tid: source file recorded but missing on disk: $f"
    elif [[ "$sstatus" == "proven" || "$sstatus" == "proven-with-postulates" ]]; then
      if ! manifest_is_gated "$src_mdir/MANIFEST" "$f"; then
        fail "$tid: proven source file '$f' is not listed as 'gated' in $src_mdir/MANIFEST"
      fi
    fi
  done

  # (c) flags: for Agda source legs, what the instrument passes, what the files
  # declare, and the union the ledger claims must agree. For Idris2 engineering
  # source legs (PROOF-POLICY §1), `%default total` must be active outside comments.
  if [ "$sprover" = "agda" ]; then
    actual_file_opts="$(file_agda_options "${src_files[@]}")"
    if [ "$rec_cli" != "$AGDA_CLI_FLAGS" ]; then
      fail "$tid: flags drift — scripts/check-proofs.sh invokes 'agda ${AGDA_CLI_FLAGS}' but the ledger records CLI '${rec_cli:-<missing>}'"
    fi
    if [ "$rec_file_opts" != "$actual_file_opts" ]; then
      fail "$tid: flags drift — the proof files declare '${actual_file_opts:-<none>}' in {-# OPTIONS #-} but the ledger records '${rec_file_opts:-<missing>}'"
    fi
    effective_expected="$(printf '%s %s\n' "$actual_file_opts" "$AGDA_CLI_FLAGS" | tr ' ' '\n' | grep -v '^$' | sort -u | tr '\n' ' ' | sed 's/ *$//')"
    if [ "$rec_effective" != "$effective_expected" ]; then
      fail "$tid: effective safety flags recorded as '${rec_effective:-<missing>}' but the files+instrument actually apply '${effective_expected:-<none>}'"
    fi
    case " $rec_effective " in
      *" --safe "*) ;;
      *) fail "$tid: '--safe' is not in the effective flags — postulates and other escape hatches are not ruled out, so the grade is unsupported (mathesis §5)" ;;
    esac

    # (d) mathesis §5 names the Agda Grade 3 configurations parenthetically
    # (--safe --erasure, or Full --cubical). If the flags in force are neither,
    # the deviation must be recorded rather than glossed over.
    grade3_named=0
    case " $rec_effective " in *" --erasure "*) grade3_named=1 ;; esac
    case " $rec_effective " in
      *" --cubical "*)
        case " $rec_effective " in
          *" --cubical-compatible "*) ;;
          *) grade3_named=1 ;;
        esac
        ;;
    esac
    if [ "$grade3_named" -eq 0 ]; then
      deviation="$(
        jq -r --arg id "$tid" '.theorems[] | select(.id == $id) | .grade_deviation // ""' "$LEDGER"
      )"
      if [ -z "${deviation// }" ]; then
        fail "$tid: the flags in force ('$rec_effective') are neither of the configurations mathesis §5 names for grade 3 (--safe --erasure, or Full --cubical) — record the deviation in .grade_deviation instead of paraphrasing the policy"
      fi
    fi
  elif [ "$sprover" = "idris2" ]; then
    for f in "${src_files[@]}"; do
      [[ -f "$f" ]] || continue
      if ! bash "$ROOT/scripts/proof-scan-dangerous.sh" --strip-comments "$f" | grep -qE '^[[:space:]]*%default[[:space:]]+total\b'; then
        fail "$tid: Idris2 source file '$f' must declare '%default total' outside comments (PROOF-POLICY §1)"
      fi
    done
  fi

  # (e) the statement must rest on named declarations that exist outside
  # comments. A grade anchored to a file or commented-out text is the "proof
  # inflation" mathesis §11 rejects.
  # Cache comment-stripped source once per recorded source file so both anchor
  # and formal-type checks inspect non-comment declarations without spawning
  # redundant subshells across large control suites.
  declare -A stripped_src_cache=()
  for f in "${src_files[@]}"; do
    [[ -f "$f" ]] || continue
    stripped_src_cache["$f"]="$(bash "$ROOT/scripts/proof-scan-dangerous.sh" --strip-comments "$f")"
  done

  if [ -z "${anchor_ids// }" ]; then
    fail "$tid: no .statement_anchor — a grade must point at the named declarations that carry the statement, not at a file"
  else
    IFS=',' read -r -a anchors <<< "$anchor_ids"
    for a in "${anchors[@]}"; do
      [ -z "${a// }" ] && continue
      hit=0
      for f in "${src_files[@]}"; do
        [ -f "$f" ] || continue
        printf '%s\n' "${stripped_src_cache[$f]}" \
          | grep -qE "^[[:space:]]*${a//./\\.}[[:space:]]*:" && hit=1
      done
      [ "$hit" -eq 1 ] || fail "$tid: statement anchor '$a' is not declared in any recorded source file (looked in: $files_csv)"
    done
  fi

  # (e2) PROOF-POLICY §2 needs a statement comparison between the Agda source
  # and any recheck leg, and check-proofs.sh queries Print Assumptions / #print
  # axioms against .statement_formal.declarations. Require a non-empty array
  # covering every .statement_anchor, and verify each recorded declaration's
  # TYPE is still present outside comments in the source file, whitespace-normalised.
  formal_decl_count="$(jq -r --arg id "$tid" '
    .theorems[] | select(.id == $id)
    | if (.statement_formal.declarations | type) == "array" then (.statement_formal.declarations | length) else -1 end' "$LEDGER")"
  if [[ "${formal_decl_count:-0}" -le 0 ]]; then
    fail "$tid: .statement_formal.declarations must be a non-empty array — recheck statement comparison (PROOF-POLICY §2) and kernel assumption queries (#131) cannot run without recorded formal declarations"
  elif [[ -n "${anchor_ids// }" ]]; then
    missing_formal_anchors="$(jq -r --arg id "$tid" '
      .theorems[] | select(.id == $id) as $t
      | ([$t.statement_anchor[]? // empty]) - ([$t.statement_formal.declarations[]?.name // empty])
      | join(", ")' "$LEDGER")"
    if [[ -n "$missing_formal_anchors" ]]; then
      fail "$tid: .statement_formal.declarations is missing formal signature(s) for statement_anchor entry/entries: $missing_formal_anchors"
    fi
  fi
  while IFS=$'\x1f' read -r decl_name decl_type; do
    [ -z "${decl_name// }" ] && continue
    if [ -z "${decl_type// }" ]; then
      fail "$tid: statement_formal.$decl_name records no type — a recheck leg cannot be compared against it"
      continue
    fi
    norm_type="$(printf '%s' "$decl_type" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
    found=0
    for f in "${src_files[@]}"; do
      [[ -f "$f" ]] || continue
      norm_file=" $(printf '%s\n' "${stripped_src_cache[$f]}" | tr -s '[:space:]' ' ') "
      case "$norm_file" in
        *" ${decl_name} : ${norm_type} "*) found=1 ;;
      esac
    done
    if [[ "$found" -eq 0 ]]; then
      fail "$tid: statement drifted — statement_formal.$decl_name records the type
     '$norm_type'
     which no recorded source file declares under '$decl_name : ...' any more.
     If the Agda statement changed, re-record it here (and re-check any leg that
     was compared against it) — PROOF-POLICY §2's statement comparison is void otherwise."
    fi
  done < <(jq -r --arg id "$tid" '
    .theorems[] | select(.id == $id) | .statement_formal.declarations[]? |
    [ (.name // ""), (.type // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

  # (f) "no escape hatches" has to be evidenced by a mechanism, not a claim.
  if [ -z "${escape_evidence// }" ]; then
    fail "$tid: no .escape_hatch_evidence — the absence of postulates has to be evidenced by a mechanism (--safe plus the comment-aware scan), not asserted"
  fi
done < <(jq -r '
  .theorems[] |
  [ .id,
    (.source.prover // ""),
    (.source.status // ""),
    ((.source.flags_provenance.file_options // []) | sort | join(" ")),
    ((.source.flags_provenance.cli // []) | sort | join(" ")),
    ((.source.safety_flags // []) | sort | join(" ")),
    ((.source.files // []) | join(",")),
    ((.statement_anchor // []) | join(",")),
    (.source.escape_hatch_evidence // "")
  ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 3c. Superseded / Regressed (mathesis §6) --------------------------------
# §6 requires a proof's history to record when it is superseded or regresses.
# Two rules make that real rather than decorative:
#   * every history entry is well formed (date, target, from, to, evidence);
#   * the LAST entry for a target must equal that target's current value — so a
#     downgrade cannot be quietly applied, and a record cannot be quietly
#     dropped. A transition to a weaker state must also carry a reason.
GRADE_STRENGTH='{"1":4,"2ii":3,"2i":2,"3":1}'
while IFS=$'\x1f' read -r tid target from to date evidence reason; do
  [ -z "$tid" ] && continue
  if [ -z "${target// }" ]; then
    fail "$tid: history entry has no target (expected 'grade' or a prover name)"
    continue
  fi
  printf '%s' "$date" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' \
    || fail "$tid/$target: history date '${date:-<missing>}' is not YYYY-MM-DD"
  [ -n "${evidence// }" ] \
    || fail "$tid/$target: history entry ${from:-?}->${to:-?} has no evidence — a recorded transition needs the receipt that showed it"
  [ -n "${from// }" ] && [ -n "${to// }" ] \
    || fail "$tid/$target: history entry has an empty from/to"

  if [ "$target" = "grade" ]; then
    for g in "$from" "$to"; do
      case "$g" in 3|2i|2ii|1) ;; *) fail "$tid: history records grade '$g', which is not one of 3, 2i, 2ii, 1 (mathesis §5)" ;; esac
    done
  else
    case ",$target," in
      *,agda,*|*,rocq,*|*,lean4,*|*,idris2,*|*,isabelle,*|*,"tla+",*|*,smt,*) ;;
      *) fail "$tid: history target '$target' is not a prover in this estate's vocabulary" ;;
    esac
    case "$to" in
      open|argued|tested-only|proven-with-postulates|proven) ;;
      *) fail "$tid/$target: history records status '$to', which is outside the PROOF-POLICY §5 vocabulary" ;;
    esac
    case "$from" in
      open|argued|tested-only|proven-with-postulates|proven) ;;
      *) fail "$tid/$target: history records status '$from', which is outside the PROOF-POLICY §5 vocabulary" ;;
    esac
  fi

  # a transition to a weaker state must say why (mathesis §6: Regressed)
  if [ "$target" = "grade" ]; then
    old_rank="$(printf '%s' "$GRADE_STRENGTH" | jq -r --arg g "$from" '.[$g] // 0')"
    new_rank="$(printf '%s' "$GRADE_STRENGTH" | jq -r --arg g "$to" '.[$g] // 0')"
    if [ "$new_rank" -lt "$old_rank" ] && [ -z "${reason// }" ]; then
      fail "$tid: grade regressed from '$from' to '$to' with no .reason recorded (mathesis §6 requires Regressed to be explained)"
    fi
  else
    if [ "$to" = "open" ] && [ "$from" != "open" ] && [ -z "${reason// }" ]; then
      fail "$tid/$target: leg regressed from '$from' to open with no .reason recorded (mathesis §6)"
    fi
  fi
done < <(jq -r '
  .theorems[] | .id as $id | (.history // [])[] |
  [ $id, (.target // ""), (.from // ""), (.to // ""), (.date // ""), (.evidence // ""), (.reason // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# the last entry for each target must be the current value
while IFS=$'\x1f' read -r tid target last_to; do
  [ -z "$tid" ] && continue
  if [ "$target" = "grade" ]; then
    current="$(jq -r --arg id "$tid" '.theorems[] | select(.id == $id) | .grade | tostring' "$LEDGER")"
    [ "$last_to" = "$current" ] \
      || fail "$tid: history's last recorded grade is '$last_to' but the ledger now records '$current' — record the regression (or the promotion) instead of rewriting history (mathesis §6)"
  else
    current="$(jq -r --arg id "$tid" --arg p "$target" '.theorems[] | select(.id == $id) | .legs[]? | select(.prover == $p) | .status' "$LEDGER" | head -1)"
    # A transition may concern the SOURCE leg rather than a recheck leg (e.g. a
    # re-baselining under a new canonical invocation). Fall back to .source.
    if [ -z "$current" ]; then
      current="$(jq -r --arg id "$tid" --arg p "$target" '.theorems[] | select(.id == $id) | select(.source.prover == $p) | .source.status' "$LEDGER" | head -1)"
    fi
    if [ -z "$current" ]; then
      fail "$tid: history records a transition for '$target', but the ledger has no such leg"
    elif [ "$last_to" != "$current" ]; then
      fail "$tid/$target: history's last recorded status is '$last_to' but the leg now records '$current' — record the change instead of rewriting history (mathesis §6)"
    fi
  fi
done < <(jq -r '
  .theorems[] | .id as $id
  | (.history // []) | group_by(.target)[] | .[-1]
  | [ $id, (.target // ""), (.to // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 3d. the trust base beyond this repo -------------------------------------
# PROOF-POLICY §1.1 (a caller is proved only *relative to* an ASSUMED contract),
# §3 (any axioms the Agda proof rests on belong in that leg's trust boundary) and
# §2.2 (per-theorem assumptions, recorded) all say the same thing: what a proof
# leans on has to be named, and named accurately. A dependency that is itself a
# proof-bearing system with open obligations is not a version string.
while IFS=$'\x1f' read -r tid aname akind arelation aev aaxioms aclaim aversion acommit; do
  [ -z "${aname// }" ] && continue
  [ -n "${akind// }" ] || fail "$tid: assumption '$aname' has no kind — an untagged assumption is an unnamed one"
  case "$akind" in
    dependency-pin|external-development) ;;
    *) fail "$tid: assumption '$aname' has kind '${akind}', which is not one of dependency-pin | external-development" ;;
  esac
  if [ "$akind" = "dependency-pin" ]; then
    # A dependency-pin that names no version and no commit pins nothing; it is a
    # dependency *mention*. Without this, deleting `version` from the Agda row
    # left a recorded assumption that constrained nothing and the audit passed.
    if [ -z "${aversion// }" ] && [ -z "${acommit// }" ]; then
      fail "$tid: dependency-pin '$aname' records neither a version nor a commit — a dependency that pins nothing is not a pin (§2.2)"
    fi
  fi
  if [ "$akind" = "external-development" ]; then
    [ -n "${arelation// }" ] || fail "$tid: external development '$aname' records no relation — say what it is to this proof (construction-under-comparison, proof-bearing-consumer, ...)"
    [ -n "${aev// }" ] || fail "$tid: external development '$aname' records no evidence — a claim about another repository needs the file and date it was read from"
  fi
  # A known open obligation must be said out loud in the theorem's caveats, by
  # name. This is the §1.1 rule applied to a whole dependency rather than to one
  # contract: the caller is never unconditionally proven while the thing it rests
  # on has open obligations.
  trigger=""
  [ -n "${aaxioms// }" ] && [ "$aaxioms" != "0" ] && trigger="undischarged axioms ($aaxioms)"
  [ "$aclaim" = "open" ] && trigger="${trigger:+$trigger; }open identity claim"
  if [ -n "$trigger" ]; then
    if ! jq -r --arg id "$tid" '.theorems[] | select(.id == $id) | (.caveats // [])[]' "$LEDGER" \
         | grep -Fiq -- "$aname"; then
      fail "$tid: '$aname' carries $trigger, but no entry in .caveats names it — the theorem would be read as if that obligation did not exist (§1.1, §3)"
    fi
  fi
done < <(jq -r '
  .theorems[] | .id as $id | (.source.assumptions // [])[] |
  [ $id, (.name // ""), (.kind // ""), (.relation // ""), (.evidence // ""),
    ((.undischarged_axioms // "") | tostring), (.identity_claim // ""),
    (.version // ""), (.commit // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# import cone: Agda's --safe refuses an import that is not itself safe, so the
# cone is the trust base. If the record admits a postulated module inside it,
# Validate .source.axioms independently of import_cone, and require an explicit
# .source.import_cone.modules audit whenever an Agda source imports external
# non-stdlib modules (for example Echo / EchoCharacteristic / EchoLinear).
while IFS=$'\x1f' read -r tid sprover sstatus sfiles_csv saxioms_state; do
  [[ -z "$tid" ]] && continue
  if [[ "$saxioms_state" == "bad" ]]; then
    fail "$tid: .source.axioms must be null or a JSON array of non-empty strings (never 'sorryAx')"
  elif [[ "$sstatus" == "proven" && "$saxioms_state" != "0" ]]; then
    fail "$tid: source.status is 'proven' but .source.axioms lists $saxioms_state axiom(s) — record 'proven-with-postulates' (§5)"
  elif [[ "$sstatus" == "proven-with-postulates" && "$saxioms_state" == "0" ]]; then
    fail "$tid: source.status is 'proven-with-postulates' with an empty .source.axioms list (§5: list the axioms)"
  fi

  if [[ "$sprover" == "agda" && -n "$sfiles_csv" ]]; then
    IFS=',' read -r -a agda_src_files <<<"$sfiles_csv"
    local_mods=" "
    for af in "${agda_src_files[@]}"; do
      [[ -f "$af" ]] || continue
      base_mod="$(basename "$af")"
      base_mod="${base_mod%.lagda.*}"
      base_mod="${base_mod%.lagda}"
      base_mod="${base_mod%.agda}"
      local_mods="${local_mods}${base_mod} "
    done
    ext_imports=""
    for af in "${agda_src_files[@]}"; do
      [[ -f "$af" ]] || continue
      while IFS= read -r imod; do
        [[ -z "$imod" ]] && continue
        case "$imod" in
          Agda.*|Data.*|Relation.*|Function|Function.*|Level|Level.*| Algebra.*|Category.*|Codata.*|Effect.*|Foreign.*|IO|IO.*|Induction.*|Reflection|Reflection.*|Strict|Text.*)
            continue ;;
        esac
        case "$local_mods" in
          *" $imod "*) continue ;;
        esac
        ext_imports="${ext_imports}${imod}"$'\n'
      done < <(sed -nE 's/^[[:space:]]*(open[[:space:]]+)?import[[:space:]]+([A-Za-z0-9_.]+).*/\2/p' "$af")
    done
    if [[ -n "${ext_imports//[[:space:]]/}" ]]; then
      cone_mods="$(jq -r --arg id "$tid" '[.theorems[] | select(.id == $id) | (.source.import_cone.modules // [])[]?.module // empty] | join("\n")' "$LEDGER")"
      if [[ -z "${cone_mods//[[:space:]]/}" ]]; then
        fail "$tid: Agda source imports external module(s) ($(printf '%s' "$ext_imports" | sort -u | tr '\n' ' ' | sed 's/ *$//')) but .source.import_cone.modules is missing or empty — audit external imports for postulates (§3)"
      else
        while IFS= read -r imod; do
          [[ -z "$imod" ]] && continue
          if ! printf '%s\n' "$cone_mods" | grep -Fxq -- "$imod"; then
            fail "$tid: Agda source imports external module '$imod', which is missing from .source.import_cone.modules (§3)"
          fi
        done < <(printf '%s' "$ext_imports" | sort -u)
      fi
    fi
  fi
done < <(jq -r '
  .theorems[] | [
    .id,
    (.source.prover // ""),
    (.source.status // ""),
    ((.source.files // []) | join(",")),
    (if (.source.axioms // null) == null then "0"
     elif (.source.axioms | type) != "array" or (all(.source.axioms[]; type == "string" and length > 0) | not) or ((.source.axioms | index("sorryAx")) != null) then "bad"
     else (.source.axioms | length | tostring) end)
  ] | join("\u001f")' "$LEDGER")

# the source leg cannot be plain `proven` (§3: list the axioms).
while IFS=$'\x1f' read -r tid mod count; do
  [ -z "${mod// }" ] && continue
  printf '%s' "$count" | grep -qE '^[0-9]+$' \
    || { fail "$tid: import cone entry '$mod' has a non-numeric postulate count '${count}'"; continue; }
  if [ "$count" -gt 0 ]; then
    sstatus="$(jq -r --arg id "$tid" '.theorems[] | select(.id == $id) | .source.status' "$LEDGER")"
    naxioms="$(jq -r --arg id "$tid" '[.theorems[] | select(.id == $id) | (.source.axioms // [])[]] | length' "$LEDGER")"
    if [ "$sstatus" != "proven-with-postulates" ]; then
      fail "$tid: import cone module '$mod' has $count postulate(s), so the source leg cannot be '$sstatus' — record it as 'proven-with-postulates' and list them (§3, §5)"
    elif [ "$naxioms" -lt 1 ]; then
      fail "$tid: import cone module '$mod' has $count postulate(s) but .source.axioms lists none (§5: list the axioms)"
    fi
  fi
done < <(jq -r '
  .theorems[] | .id as $id | (.source.import_cone.modules // [])[] |
  [ $id, (.module // ""), ((.postulates // "") | tostring) ] | map(tostring) | join("\u001f")' "$LEDGER")

# An open leg with no caveat is a claim by omission: a reader who skims the
# grade must still meet the fact that the theorem is not fully rechecked.
while IFS=$'\x1f' read -r tid open_count caveat_count; do
  [ -z "$tid" ] && continue
  if [ "${open_count:-0}" -gt 0 ] && [ "${caveat_count:-0}" -lt 1 ]; then
    fail "$tid: $open_count leg(s) are open and .caveats is empty — say in the record that the theorem is not fully rechecked"
  fi
done < <(jq -r '
  .theorems[] | [ .id,
    ([.legs[]? | select(.status == "open")] | length),
    ((.caveats // []) | length) ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 3d2. related but not relied upon ---------------------------------------
# A sibling formalisation of the same object is the most likely thing a reader
# will mistake for evidence. It is not an assumption (nothing rests on it) and it
# is not evidence for this theorem (it proves something else), so it gets its own
# array and must say so explicitly.
while IFS=$'\x1f' read -r tid name relation consumed ev; do
  [ -z "$tid" ] && continue
  [ -n "${name// }" ] || fail "$tid: related development with no name"
  [ -n "${relation// }" ] || fail "$tid: related development '$name' records no relation — say how it relates, since it is not being consumed"
  [ -n "${ev// }" ] || fail "$tid: related development '$name' records no evidence (file and date read)"
  if [ "$consumed" = "true" ]; then
    fail "$tid: related development '$name' claims to be consumed — then it belongs in .source.assumptions, and here it would double-count"
  fi
done < <(jq -r '
  .theorems[] | .id as $id | (.source.related_developments // [])[] |
  [ $id, (.name // ""), (.relation // ""),
    ((.consumed_by_this_proof // false) | tostring), (.evidence // "") ]
  | map(tostring) | join("\u001f")' "$LEDGER")

# --- 3e. waivers: PROOF-POLICY §4 -------------------------------------------
# A waiver is for a statement the mapped prover cannot express. It is not a
# softer status token: a waived leg carries NO status at all (so nothing can
# count it), it names the obligation, the tool and the reason, and it points at
# the exception record. Nothing here lets a waiver create a grade.
while IFS=$'\x1f' read -r tid prover wstatus wobligation wtool wreason wrecord; do
  [ -z "$tid" ] && continue
  if [ -n "${wstatus// }" ] && [ "$wstatus" != "null" ]; then
    fail "$tid/$prover: a waived leg also carries status '$wstatus' — a waiver is not a status token (§4)"
  fi
  for pair in "obligation:${wobligation}" "tool:${wtool}" "reason:${wreason}" "record:${wrecord}"; do
    if [ -z "${pair#*:}" ] || [ "${pair#*:}" = "null" ]; then
      fail "$tid/$prover: waiver without '${pair%%:*}' — §4 requires the obligation, the tool, the reason and the exception record"
    fi
  done
  if [ -n "$wtool" ] && [ "$wtool" != "null" ]; then
    tool_matches_leg=0
    case "$prover:$wtool" in
      rocq:rocq|rocq:coq|coq:rocq|coq:coq) tool_matches_leg=1 ;;
      lean4:lean4|lean4:lean|lean:lean4|lean:lean) tool_matches_leg=1 ;;
      *) [ "$wtool" = "$prover" ] && tool_matches_leg=1 ;;
    esac
    if [ "$tool_matches_leg" -eq 0 ]; then
      fail "$tid/$prover: .waiver.tool '$wtool' does not match leg prover '$prover' — a waiver must bind to the waived leg's own prover (§4)"
    fi
  fi
  # The record must RESOLVE, not merely be non-empty. Accepting any string let a
  # required leg carry `record: does-not-exist` and still pass: the presence
  # check was satisfied, and the waiver then removed that leg from the status
  # and artifact rules below. A record is `<path>[#<anchor>]` in this
  # repository; when an anchor is given it must occur in the file, and the file
  # must name the tool, so the citation actually binds to this waiver. An
  # external ruling belongs in a file here that cites it.
  wrec_path="${wrecord%%#*}"
  wrec_anchor=""
  case "$wrecord" in *'#'*) wrec_anchor="${wrecord#*#}" ;; esac
  if [ ! -f "$wrec_path" ]; then
    fail "$tid/$prover: waiver record '$wrecord' does not resolve — no file '$wrec_path' in the repository (§4)"
  else
    if [ -n "$wrec_anchor" ] && ! grep -qiF -- "$wrec_anchor" "$wrec_path"; then
      fail "$tid/$prover: waiver record '$wrecord' names anchor '$wrec_anchor', which does not occur in $wrec_path (§4)"
    fi
    if ! grep -qiF -- "$wtool" "$wrec_path"; then
      fail "$tid/$prover: waiver record '$wrecord' never mentions the tool '$wtool' — the record does not bind to this waiver (§4)"
    fi
  fi
  WAIVERS+=("$tid: $prover leg WAIVED — ${wreason} (tool: ${wtool}; record: ${wrecord})")
done < <(jq -r '
  .theorems[] as $t | $t.legs[]? | select(.waiver != null) |
  [ $t.id, .prover, (.status // ""), (.waiver.obligation // ""), (.waiver.tool // ""),
    (.waiver.reason // ""), (.waiver.record // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 4. every non-open claim must be backed by artifact + MANIFEST + route ---
# Nine emitted fields, nine names — in order: id, prover, status, artifact,
# route, statement_compared, axioms, reproof_reason, blocker. A dropped name
# here silently shifts every later field left (blocker would receive the
# reproof_reason), which is how a rule ends up never firing.
while IFS=$'\x1f' read -r tid prover status artifact route compared axioms reproof_reason blocker; do
  [ -z "$tid" ] && continue
  # Waived legs are audited in 3e and carry no claim here.
  [ -z "${status// }" ] && continue

  # PROOF-POLICY §2.2: a leg declares `transported`, `re-proved` or
  # `unavailable`. The route is a property of the leg, not of the claim, so it
  # is checked before the open/claimed split.
  case "${route:-}" in
    ""|null)
      if [ "$status" != "open" ]; then
        fail "$tid/$prover: status '$status' recorded with no route — say whether it was transported or re-proved (§2.2)"
      fi
      ;;
    transported|re-proved) ;;
    unavailable)
      # 'unavailable' is a statement about the route, not a proof: it cannot
      # carry a claim, and it must say what is missing.
      if [ "$status" != "open" ]; then
        fail "$tid/$prover: route 'unavailable' with status '$status' — a route that does not exist cannot support a claim (§2.2)"
      fi
      if [ -z "${blocker// }" ] || [ "$blocker" = "null" ]; then
        fail "$tid/$prover: route 'unavailable' with no blocker recorded — say what the missing route is (§2.2)"
      fi
      ;;
    *) fail "$tid/$prover: route '${route}' is not one of transported, re-proved, unavailable (PROOF-POLICY §2.2)" ;;
  esac

  [ "$status" = "open" ] && continue

  if [ -z "$artifact" ] || [ "$artifact" = "null" ]; then
    fail "$tid/$prover: status '$status' recorded with no artifact"
    continue
  fi
  if [ ! -f "$artifact" ]; then
    fail "$tid/$prover: artifact listed but missing on disk: $artifact"
    continue
  fi

  # The artifact must be gated in the prover's MANIFEST, or the compile step
  # (scripts/check-proofs.sh) would never touch it.
  case "$prover" in
    rocq) mdir="$PROOFS_DIR/coq" ;;
    lean4) mdir="$PROOFS_DIR/lean4" ;;
    agda) mdir="$PROOFS_DIR/agda" ;;
    idris2) mdir="$PROOFS_DIR/idris2" ;;
    *) mdir="" ;;
  esac
  # A prover the lane has no recipe for cannot support a claim. Without this the
  # default branch left $mdir empty, skipped every manifest check, and a 'proven'
  # Isabelle/SMT/TLA+ row pointing at any file on disk would count towards a
  # grade with nothing having run. The wired set is the set check-proofs.sh
  # implements; write it out here so the two cannot drift silently.
  if [ -z "$mdir" ]; then
    fail "$tid/$prover: status '$status' recorded for a prover the lane cannot compile — scripts/check-proofs.sh wires idris2, lean4, agda and coq only, so this leg would contribute to a grade without any proof system running. Record the leg as open, or add a compile recipe for '$prover' first (PROOF-POLICY §2.3)."
    continue
  fi
  if [[ -n "$mdir" ]]; then
    if [[ ! -f "$mdir/MANIFEST" ]]; then
      fail "$tid/$prover: $mdir/MANIFEST is missing, so $artifact cannot be compiled by the lane"
    elif ! manifest_is_gated "$mdir/MANIFEST" "$artifact"; then
      fail "$tid/$prover: $artifact is not listed as 'gated' in $mdir/MANIFEST (unlisted or quarantined witness)"
    fi
  fi

  # Optional support_files (helper modules imported by .artifact): every entry
  # must exist on disk, be gated in the same MANIFEST, and obey the Mathlib ban.
  sup_type="$(jq -r --arg id "$tid" --arg p "$prover" '
    [ .theorems[] | select(.id == $id) | .legs[]? | select(.prover == $p)
      | if (.support_files // null) == null then "none"
        elif (.support_files | type) == "array" and all(.support_files[]; type == "string" and length > 0) then "ok"
        else "bad" end ][0] // "none"' "$LEDGER")"
  if [[ "$sup_type" == "bad" ]]; then
    fail "$tid/$prover: .support_files must be an array of non-empty file path strings"
  elif [[ "$sup_type" == "ok" ]]; then
    art_idx="$(manifest_gated_index "$mdir/MANIFEST" "$artifact" || echo 0)"
    while IFS= read -r sf; do
      [[ -z "$sf" ]] && continue
      if [[ ! -f "$sf" ]]; then
        fail "$tid/$prover: support file listed but missing on disk: $sf"
      elif ! sf_idx="$(manifest_gated_index "$mdir/MANIFEST" "$sf")"; then
        fail "$tid/$prover: support file '$sf' is not listed as 'gated' in $mdir/MANIFEST"
      elif [[ "$art_idx" -gt 0 && "$sf_idx" -ge "$art_idx" ]]; then
        fail "$tid/$prover: support file '$sf' must appear BEFORE '$artifact' in $mdir/MANIFEST so its compiled artifact exists when the witness compiles"
      elif [[ "$prover" == "lean4" ]] && grep -qE '^[[:space:]]*import[[:space:]]+Mathlib' "$sf"; then
        fail "$tid/$prover: support file '$sf' imports Mathlib, which PROOF-POLICY §2 forbids"
      fi
    done < <(jq -r --arg id "$tid" --arg p "$prover" '
      .theorems[] | select(.id == $id) | .legs[]? | select(.prover == $p) | (.support_files // [])[]' "$LEDGER")
  fi

  # PROOF-POLICY §2.3: record the route; §2.1/§2.2: without an affirmative
  # statement comparison the leg is ASSUMED (argued), not PROVEN.
  if [[ "$route" == "re-proved" ]] && { [[ -z "$reproof_reason" ]] || [[ "$reproof_reason" == "null" ]]; }; then
    fail "$tid/$prover: route 're-proved' requires a reproof_reason (PROOF-POLICY §2.2)"
  fi
  if [[ "$status" == "proven" || "$status" == "proven-with-postulates" ]]; then
    case "${compared,,}" in
      ""|null|none|false|no)
        fail "$tid/$prover: '$status' requires an affirmative statement comparison (PROOF-POLICY §2.1/§2.2); without it the leg is 'argued'" ;;
    esac
  fi

  # §5: axioms must be a JSON array of strings, never contain sorryAx, and only
  # proven-with-postulates may carry a non-empty axiom list.
  axiom_check="$(jq -r --arg id "$tid" --arg p "$prover" '
    [ .theorems[] | select(.id == $id) | .legs[]? | select(.prover == $p)
      | if (.axioms | type) != "array" or (all(.axioms[]; type == "string" and length > 0) | not) then "not-string-array"
        elif (.axioms | index("sorryAx")) != null then "has-sorryAx"
        else (.axioms | length | tostring) end ][0] // "not-string-array"' "$LEDGER")"
  if [[ "$axiom_check" == "not-string-array" ]]; then
    fail "$tid/$prover: 'axioms' must be recorded as a JSON array of strings (empty [] when none) — mathesis §6 axiom tracking"
  elif [[ "$axiom_check" == "has-sorryAx" ]]; then
    fail "$tid/$prover: 'sorryAx' is an incomplete-proof marker, never a permissible axiom in .axioms"
  elif [[ "$status" == "proven" && "$axiom_check" -ne 0 ]]; then
    fail "$tid/$prover: status 'proven' but $axiom_check axiom(s) recorded; that is 'proven-with-postulates' (§5)"
  elif [[ "$status" == "proven-with-postulates" && "$axiom_check" -eq 0 ]]; then
    fail "$tid/$prover: status 'proven-with-postulates' with an empty axiom list (§5: list the axioms)"
  fi

  # Target declarations + kernel-assumption receipt check for Rocq/Lean witnesses
  # (nextgen-typing#131): check-proofs.sh queries Print Assumptions / #print axioms
  # on every target declaration, so each formal anchor must resolve to a distinct,
  # valid target-prover identifier, and promoted legs must record evidence.
  if [[ ( "$status" == "proven" || "$status" == "proven-with-postulates" ) && ( "$prover" == "rocq" || "$prover" == "lean4" ) ]]; then
    decl_audit="$(jq -r --arg id "$tid" --arg p "$prover" '
      .theorems[] | select(.id == $id) as $t
      | ([ $t.statement_formal.declarations[]?.name // empty ]) as $anchors
      | ($t.legs[] | select(.prover == $p)) as $leg
      | if ($leg.declarations // null) != null then
          if ($leg.declarations | type) != "array" or ($leg.declarations | length) == 0 then
            "ERR:legs[].declarations must be a non-empty array"
          else
            ([ $leg.declarations[] | if type == "object" then (.name // "") else tostring end ]) as $names
            | ([ $leg.declarations[] | select(type == "object") | (.anchor // "") ]) as $mapped_anchors
            | if ($names | unique | length) != ($names | length) then
                "ERR:legs[].declarations maps multiple anchors to the same target declaration"
              elif ($anchors | length) > 0 and (($mapped_anchors | length) > 0) and (($anchors - $mapped_anchors) | length) > 0 then
                "ERR:legs[].declarations is missing anchor mapping(s): " + (($anchors - $mapped_anchors) | join(", "))
              elif ($anchors | length) > 0 and ($names | length) < ($anchors | length) then
                "ERR:legs[].declarations lists fewer declarations than statement_formal.declarations"
              else
                "OK:" + ($names | join(","))
              end
          end
        elif ($anchors | length) > 0 then
          "OK:" + ($anchors | join(","))
        else
          "ERR:no declarations recorded in statement_formal.declarations or legs[].declarations"
        end' "$LEDGER")"
    if [[ "$decl_audit" == ERR:* ]]; then
      fail "$tid/$prover: ${decl_audit#ERR:}"
    else
      IFS=',' read -r -a leg_decls <<<"${decl_audit#OK:}"
      for dname in "${leg_decls[@]}"; do
        if ! is_valid_target_ident "$dname"; then
          fail "$tid/$prover: declaration '$dname' is not a valid $prover identifier — map hyphenated Agda anchors to $prover identifiers in legs[].declarations"
        fi
      done
    fi

    IFS=$'\x1f' read -r le_commit le_run le_assumptions < <(jq -r --arg id "$tid" --arg p "$prover" '
      .theorems[] | select(.id == $id) | .legs[] | select(.prover == $p) | (.evidence // {}) |
      [ (.commit // ""), (.run // ""), (.assumptions_output // "") ] | map(tostring) | join("\u001f")' "$LEDGER")
    if ! [[ "${le_commit:-}" =~ ^[0-9a-f]{40}$ ]] || [[ -z "${le_run//[[:space:]]/}" ]] || [[ -z "${le_assumptions//[[:space:]]/}" ]]; then
      fail "$tid/$prover: '$status' recheck leg must record .evidence with a 40-character .commit, .run, and verbatim .assumptions_output from Print Assumptions / #print axioms (mathesis §6, issue #131)"
    fi
  fi

  # §2: no Mathlib. A proof that needs a large external library is a
  # dependency, not a proof the estate owns.
  if [[ "$prover" == "lean4" ]] && grep -qE '^[[:space:]]*import[[:space:]]+Mathlib' "$artifact"; then
    fail "$tid/$prover: $artifact imports Mathlib, which PROOF-POLICY §2 forbids"
  fi
done < <(jq -r '
  .theorems[] as $t | $t.legs[]? | select(.waiver == null) |
  [ $t.id, .prover, (.status // ""), (.artifact // ""), (.route // ""),
    (if (.statement_compared // null) == null then "" else (.statement_compared | tostring) end),
    (if (.axioms // null) == null then "" else "recorded" end),
    (.reproof_reason // ""), (.blocker // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 5. source legs: files, receipts, safety flags ---------------------------
while IFS=$'\x1f' read -r tid status files; do
  [ -z "$tid" ] && continue
  if [ -z "$files" ] || [ "$files" = "null" ]; then
    fail "$tid: source leg lists no files (zero-work)"
    continue
  fi
  IFS=',' read -r -a file_list <<<"$files"
  for f in "${file_list[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || fail "$tid: source file listed but missing: $f"
  done

  if [ "$status" = "proven" ] || [ "$status" = "proven-with-postulates" ]; then
    IFS=$'\x1f' read -r ekind ecommit edate erun < <(jq -r --arg id "$tid" '
      .theorems[] | select(.id == $id) | .source.evidence? |
      [ (.kind // ""), (.commit // ""), (.date // ""), (.run // "") ] | map(tostring) | join("\u001f")' "$LEDGER")
    for pair in "kind:${ekind:-}" "commit:${ecommit:-}" "date:${edate:-}" "run:${erun:-}"; do
      if [ -z "${pair#*:}" ]; then
        fail "$tid: source leg recorded '$status' without evidence '$pair' (mathesis §6: the receipt names the commit)"
      fi
    done
    # mathesis §6: the receipt names the exact commit it verified. The commit
    # must be a full SHA-1. Reachability is advisory, not fatal: a squash or
    # rebase merge rewrites the commit that a green run was recorded against,
    # and a gate that cannot survive the repository's own merge style would be
    # turned off rather than fixed.
    if [ -n "${ecommit:-}" ] && ! printf '%s' "$ecommit" | grep -qE '^[0-9a-f]{40}$'; then
      fail "$tid: evidence commit '$ecommit' is not a full 40-character SHA-1"
    elif [ -n "${ecommit:-}" ]; then
      if git cat-file -e "${ecommit}^{commit}" 2>/dev/null; then
        note "$tid: receipt commit ${ecommit:0:8} is reachable from this clone"
      else
        note "$tid: receipt commit ${ecommit:0:8} is not reachable here (squash/rebase merge?) — refresh the receipt"
      fi
    fi
  fi
done < <(jq -r '.theorems[] | [ .id, (.source.status // ""), ((.source.files // []) | join(",")) ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 5a. corroboration is not a receipt -------------------------------------
# A local run under a different compiler version is useful — it says the proof is
# not an artifact of one toolchain — but §2.1 pins the version *with* the result,
# and a receipt is what the grade rests on. So a corroborating run must declare
# itself as such, and must say which toolchain produced it.
while IFS=$'\x1f' read -r tid toolchain invocation result corrob; do
  [ -z "$tid" ] && continue
  [ -n "${toolchain// }" ] || fail "$tid: local evidence with no toolchain — a check that does not name its compiler cannot be reproduced (§2.1)"
  [ -n "${invocation// }" ] || fail "$tid: local evidence with no recorded invocation (§2.2)"
  [ -n "${result// }" ] || fail "$tid: local evidence with no observed result (§2.2)"
  [ "$corrob" = "true" ] || fail "$tid: local evidence must set corroboration_only: true — it cannot stand in for the pinned receipt"
done < <(jq -r '
  .theorems[] | .id as $id | (.local_evidence // [])[] |
  [ $id, (.toolchain // ""), (.invocation // ""), (.observed_result // ""),
    ((.corroboration_only // false) | tostring) ] | map(tostring) | join("\u001f")' "$LEDGER")

# --- 5b. receipt lineage: an archived receipt says why (mathesis §6) --------
# mathesis §6 introduces `Superseded` and `Regressed` as first-class states for a
# receipt. A receipt kept but not marked is indistinguishable from one that is
# still evidence, which is the drift the clause exists to stop.
while IFS=$'\x1f' read -r tid idx state why; do
  [ -z "$tid" ] && continue
  case "$state" in
    superseded|regressed) ;;
    "")
      fail "$tid: historical evidence entry $idx has no state — mathesis §6 requires 'superseded' or 'regressed', not a silently archived receipt" ;;
    *)
      fail "$tid: historical evidence entry $idx has state '${state}', which is not one of superseded | regressed (mathesis §6)" ;;
  esac
  [ -n "${why// }" ] || fail "$tid: historical evidence entry $idx does not say why it is no longer the current receipt"
done < <(jq -r '
  .theorems[] | .id as $id | (.source.evidence.historical_evidence // []) | to_entries[] |
  [ $id, (.key | tostring), (.value.state // ""),
    (.value.why_not_current // .value.reason // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

# Agda safety flags stay in force (this repository's PROOF-NEEDS.adoc).
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--safe' "$f" \
    || fail "missing safety flag: $f does not declare --safe in its OPTIONS pragma"
  grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--without-K' "$f" \
    || fail "missing safety flag: $f does not declare --without-K in its OPTIONS pragma"
done < <(jq -r '.theorems[].source.files[]? | select(endswith(".agda"))' "$LEDGER" | sort -u)

# --- 6. escape hatches + declared axioms in every proof/witness source -------
# Axioms are scoped to the specific leg(s) claiming each file (never pooled
# globally across unrelated legs), so an axiom permitted on one leg cannot
# license an undeclared axiom in another witness.
# Return success if an unwaived proven-with-postulates leg claiming the file
# lists the axiom, either by its name or with a qualified prefix. A jq failure
# also returns a non-zero status.
file_allows_axiom() {
  local file="$1" ax_name="$2"
  jq -e --arg f "$file" --arg ax "$ax_name" '
    [ .theorems[].legs[]?
      | select(.waiver == null and (.status // "open") == "proven-with-postulates")
      | select((.artifact // "") == $f or (((.support_files // []) | type) == "array" and ((.support_files // []) | index($f)) != null))
      | (.axioms // [])[]
      | select(. == $ax or endswith("." + $ax))
    ] | length > 0
  ' "$LEDGER" >/dev/null 2>&1
}

# Add escape-hatch and unrecorded axiom findings for the file to $FAILS.
scan_one() {
  local f="$1" hits
  hits="$(scan_escape_hatches "$f")"
  if [[ -n "$hits" ]]; then
    fail "escape hatch in $f:
$(printf '%s\n' "$hits" | sed 's/^/     line /')"
  fi
  local ax
  ax="$(scan_declared_axioms "$f")"
  if [[ -n "$ax" ]]; then
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      name="$(printf '%s\n' "$line" | sed -E 's/^[0-9]+:[[:space:]]*(Axiom|Parameter|Conjecture|axiom)[[:space:]]+([A-Za-z0-9_′'\'']+).*/\2/')"
      if ! file_allows_axiom "$f" "$name"; then
        fail "undeclared axiom in $f:$line — PROOF-POLICY §5 requires every axiom to be named on the owning leg in the ledger (proven-with-postulates)"
      fi
    done <<<"$ax"
  fi
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROOF_FILES="$(git ls-files -- "$PROOFS_DIR" | grep -E '\.(agda|lagda|lagda\.[A-Za-z0-9]+|idr|v|lean|tla)$' | sort)"
else
  PROOF_FILES="$(find "$PROOFS_DIR" -type f \( -name '*.agda' -o -name '*.lagda' -o -name '*.lagda.*' -o -name '*.idr' -o -name '*.v' -o -name '*.lean' -o -name '*.tla' \) 2>/dev/null | sort)"
fi
scanned=0
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  scanned=$((scanned + 1))
  scan_one "$f"
done <<<"$PROOF_FILES"

if [[ "$scanned" -eq 0 ]]; then
  fail "zero-work: no proof source or witness was scanned under $PROOFS_DIR"
fi

# --- 7. witnesses on disk must be claimed in the ledger ----------------------
# Enumerated the same way as section 6: `git ls-files` inside a work tree, a
# plain `find` otherwise. Covers Agda sources as well as Rocq and Lean witnesses.
list_witnesses() {  # $1 = prover dir under $PROOFS_DIR, $2 = extension
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$2" == "agda" ]]; then
      git ls-files -- "$PROOFS_DIR/$1" 2>/dev/null | grep -E '\.(agda|lagda|lagda\.[A-Za-z0-9]+)$' | sort
    else
      git ls-files -- "$PROOFS_DIR/$1" 2>/dev/null | grep -E "\.$2\$" | sort
    fi
  else
    if [[ "$2" == "agda" ]]; then
      find "$PROOFS_DIR/$1" -type f \( -name '*.agda' -o -name '*.lagda' -o -name '*.lagda.*' \) 2>/dev/null | sort
    else
      find "$PROOFS_DIR/$1" -type f -name "*.$2" 2>/dev/null | sort
    fi
  fi
}
LEDGER_ARTIFACTS="$(jq -r '
  [ .theorems[]
    | (if (.source.files | type) == "array" then .source.files[] else empty end),
      (.legs[]? | (.artifact // empty), (if (.support_files | type) == "array" then .support_files[] else empty end))
  ][] | select(type == "string" and length > 0)' "$LEDGER" | sort -u)"
for dir in agda coq lean4; do
  ext=v
  [[ "$dir" == "lean4" ]] && ext=lean
  [[ "$dir" == "agda" ]] && ext=agda
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    if ! printf '%s\n' "$LEDGER_ARTIFACTS" | grep -Fxq -- "$f"; then
      fail "witness on disk is not claimed in the ledger: $f
     Add a source/leg entry claiming '$f' (route, axioms, statement comparison) — an
     unclaimed witness is exactly the silent-drift case mathesis §11 rejects."
    fi
  done < <(list_witnesses "$dir" "$ext")
done

# --- 8. cross-project registry: manifest <-> boundary allowlist <-> disk -----
# Print non-empty registry entries from stdin in sorted order, after removing
# comments, quotes, spaces, tabs, carriage returns and trailing commas. An
# empty result or a pipeline failure returns a non-zero status.
normalize_list_entries() {
  sed 's/#.*//' | tr -d "\"' \t\r" | sed 's/,*$//' | grep -v '^$' | sort
}

if [ -f "$MANIFEST_SOURCE" ] && [ -f "$BOUNDARY_SCRIPT" ]; then
  manifest_list="$(awk '
    /^\[/ { in_section = ($0 ~ /^\[verification\]/); next }
    in_section && /^[[:space:]]*allowed-proofs[[:space:]]*=[[:space:]]*\[/ { in_list = 1; next }
    in_list && /^[[:space:]]*\][[:space:]]*$/ { in_list = 0; next }
    in_list { print }
  ' "$MANIFEST_SOURCE" | normalize_list_entries)"

  boundary_list="$(awk '
    /^ALLOWED_PROOFS=\(/ { in_list = 1; next }
    in_list && /^\)/ { in_list = 0; next }
    in_list { print }
  ' "$BOUNDARY_SCRIPT" | normalize_list_entries)"

  [ -n "$manifest_list" ] || fail "cross-project registry is empty in $MANIFEST_SOURCE"
  [ -n "$boundary_list" ] || fail "cross-project allowlist is empty in $BOUNDARY_SCRIPT"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    grep -Fxq -- "$entry" <<<"$boundary_list" \
      || fail "registry drift: '$entry' is in $MANIFEST_SOURCE but not in ALLOWED_PROOFS of $BOUNDARY_SCRIPT"
    [ -e "$entry" ] || fail "stale registry entry: '$entry' is registered but absent from disk"
  done <<<"$manifest_list"

  while IFS= read -r entry; do
    [ -z "$entry" ] && continue
    grep -Fxq -- "$entry" <<<"$manifest_list" \
      || fail "registry drift: '$entry' is in ALLOWED_PROOFS of $BOUNDARY_SCRIPT but not in $MANIFEST_SOURCE"
  done <<<"$boundary_list"

  # Proof sources on disk must be registered (the anti-drift rule).
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    grep -Fxq -- "$f" <<<"$manifest_list" \
      || fail "unlisted proof source: $f
     Register it in [verification].allowed-proofs of $MANIFEST_SOURCE AND in
     ALLOWED_PROOFS of $BOUNDARY_SCRIPT."
  done <<<"$PROOF_FILES"
else
  fail "cross-project registry inputs missing ($MANIFEST_SOURCE / $BOUNDARY_SCRIPT)"
fi

# --- 9. documentation must not claim a grade the ledger does not support -----
if [ -f "$DOCS_STATUS" ]; then
  grep -qF 'LEDGER.json' "$DOCS_STATUS" \
    || fail "$DOCS_STATUS does not point at the proof ledger (LEDGER.json): status prose is unanchored"
  while IFS= read -r tid; do
    [ -z "$tid" ] && continue
    grep -qF -- "$tid" "$DOCS_STATUS" \
      || fail "$DOCS_STATUS does not mention theorem '$tid' from the ledger"
  done < <(jq -r '.theorems[].id' "$LEDGER" | sort -u)

  # Per theorem, not repository-wide. The old rule only ran when NO theorem had
  # a proven leg, so one proven recheck leg anywhere switched off the comparison
  # for every theorem — a `2i` theorem could be described as Grade 1, and in a
  # multi-theorem ledger a single proof masked every other claim. The summary
  # table is the machine-readable place the page states a grade, so the gate
  # reads the row for each theorem id and compares it with that theorem's own
  # ledger grade, in both directions.
  while IFS=$'\x1f' read -r tid g; do
    [ -z "$tid" ] && continue
    claimed="$(awk -F'|' -v id="$tid" '
      /^\|/ {
        cell = $2; gsub(/^[ \t]+|[ \t]+$/, "", cell)
        if (cell == id) { g = $4; print g; exit }
      }' "$DOCS_STATUS" | tr -d '*+`' | tr -d ' \t')"
    if [ -z "$claimed" ]; then
      fail "$DOCS_STATUS has no grade row for theorem '$tid' — the summary table must carry the ledger's grade where the gate can read it (mathesis §11)"
    elif [ "$claimed" != "$g" ]; then
      fail "$DOCS_STATUS records '$tid' at Grade $claimed but the ledger says Grade $g (mathesis §5/§6: the page is a summary of the ledger, and the ledger wins)"
    fi
  done < <(jq -r '.theorems[] | [.id, (.grade | tostring)] | join("\u001f")' "$LEDGER")

  proven_total=0
  for k in "${!THEOREM_PROVEN[@]}"; do proven_total=$((proven_total + ${THEOREM_PROVEN[$k]})); done
  if [ "$proven_total" -eq 0 ]; then
    if grep -qE 'Grade[[:space:]]+(2i|2ii|2|1)\b|grade[[:space:]]+(2i|2ii|2|1)\b' "$DOCS_STATUS"; then
      fail "$DOCS_STATUS claims a Grade 2/1 result but the ledger records no proven recheck leg (mathesis §5/§11)"
    fi
  fi
else
  fail "proof status document missing: $DOCS_STATUS"
fi

# --- 10. open legs are reported, never hidden and never counted ----------
while IFS=$'\x1f' read -r tid prover status blocker; do
  [ -z "$tid" ] && continue
  [ "$status" = "open" ] || continue
  GAPS+=("$tid: $prover leg is OPEN${blocker:+ — $blocker}")
done < <(jq -r '.theorems[] as $t | $t.legs[]? | select(.status == "open") | [ $t.id, .prover, .status, (.blocker // "") ] | map(tostring) | join("\u001f")' "$LEDGER")

if [ "${#WAIVERS[@]}" -gt 0 ]; then
  echo "--- waived legs (no status token; PROOF-POLICY §4) ---"
  printf '  - %s\n' "${WAIVERS[@]}"
  echo ""
fi

# --- 11. verdict ----------------------------------------------------------
proven_legs=0
for k in "${!THEOREM_PROVEN[@]}"; do proven_legs=$((proven_legs + ${THEOREM_PROVEN[$k]})); done

if [ "${#NOTES[@]}" -gt 0 ]; then
  echo "--- notes ---"
  printf '  - %s\n' "${NOTES[@]}"
  echo ""
fi

echo "--- ledger census ---"
echo "  theorems:        $theorem_count"
echo "  proof sources:   $scanned scanned"
echo "  proven legs:     $proven_legs"
echo ""

# Annotation-visible census: the step summary is not retrievable through the
# check-run API, so the counts also go out as a notice. A reader can then see
# "1 theorem, 2 sources, 0 proven legs, 2 gaps" without the runner log.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  echo "::notice::proof ledger: ${theorem_count} theorem(s), ${scanned} proof source(s), ${proven_legs} proven recheck leg(s), ${#GAPS[@]} policy gap(s)"
fi

if [ "${#GAPS[@]}" -gt 0 ]; then
  echo "--- POLICY GAPS (legal to record; NOT counted as verification) ---"
  printf '  ! %s\n' "${GAPS[@]}"
  echo ""
fi

status="PASS"
[ "${#FAILS[@]}" -gt 0 ] && status="FAIL"

if [[ -n "$RECEIPT" ]]; then
  if ! mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null; then
    echo "FAIL: cannot create receipt directory for $RECEIPT" >&2
    exit 1
  fi
  {
    echo "proof-ledger receipt"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
    echo "runner: ${RUNNER_NAME:-local}/${RUNNER_OS:-$(uname -s)}"
    echo "status: $status"
    echo "policy: $(policy_label)${POLICY_COMMIT:+ @ $POLICY_COMMIT}${POLICY_RULING:+ ($POLICY_RULING)}${POLICY_AMENDED:+, amended $POLICY_AMENDED}"
    echo "policy-vendored-here: $POLICY_VENDORED"
    echo "grade-model: mathesis/estate-mathematical-architecture §5-§6"
    echo "theorems: $theorem_count"
    echo "proof-sources-scanned: $scanned"
    echo "proven-recheck-legs: $proven_legs"
    echo "ledger-sha256: $(sha256sum "$LEDGER" | cut -d' ' -f1)"
    echo "gaps:"
    if [[ "${#GAPS[@]}" -eq 0 ]]; then echo "  (none)"; else printf '  - %s\n' "${GAPS[@]}"; fi
    echo "waivered-legs:"
    if [[ "${#WAIVERS[@]}" -eq 0 ]]; then echo "  (none)"; else printf '  - %s\n' "${WAIVERS[@]}"; fi
    if [[ "${#FAILS[@]}" -gt 0 ]]; then
      echo "failures:"
      printf '  - %s\n' "${FAILS[@]}"
    fi
  } >"$RECEIPT" || {
    echo "FAIL: cannot write receipt $RECEIPT" >&2
    exit 1
  }
  echo "receipt written: $RECEIPT"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Proof ledger gate — **$status**"
      echo ""
      echo "| item | value |"
      echo "|------|-------|"
      echo "| theorems | $theorem_count |"
      echo "| proof sources scanned | $scanned |"
      echo "| proven recheck legs (Rocq/Lean) | $proven_legs |"
      echo "| policy gaps | ${#GAPS[@]} |"
      echo ""
      if [ "${#GAPS[@]}" -gt 0 ]; then
        echo "Policy gaps (recorded, not verified):"
        printf -- '- %s\n' "${GAPS[@]}"
        echo ""
      fi
    } >>"$GITHUB_STEP_SUMMARY"
  fi
fi

if [ "${#FAILS[@]}" -gt 0 ]; then
  echo "=== FAIL: ${#FAILS[@]} ledger violation(s) ==="
  printf '  x %s\n' "${FAILS[@]}"
  echo ""
  echo "Nothing above was treated as verified. Fix the ledger, the artifacts, or the"
  echo "registries; do not relax the vocabulary to make this gate pass."
  exit 1
fi

echo "✅ PASS: every recorded claim is backed by an artifact, a manifest entry, a"
echo "   route and a statement comparison; open legs are recorded, not hidden."
if [ "$proven_legs" -eq 0 ]; then
  echo "   NOTE: 0 recheck legs are proven (Rocq: 0, Lean: 0). No Grade 2i/2ii/1"
  echo "   claim is made by this repository and nothing here says the theorem was"
  echo "   verified in an independent kernel."
fi
exit 0
