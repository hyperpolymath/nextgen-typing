#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-proof-ledger.sh — proof-LEDGER gate for nextgen-typing.
#
# What this refuses to do, and why:
#
#   * It does NOT re-run the Agda theory proof. Under
#     standards/3-practice/PROOF-POLICY.adoc §1 a theory proof's source of
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
fail() { FAILS+=("$1"); }
note() { NOTES+=("$1"); }

# ---------------------------------------------------------------------------
# Escape-hatch scan (shared by the repo audit and the both-ways control).
# Comment-aware: PROOF-POLICY keeps escape-hatch *policy* in
# docs/TRUSTED-BASE-REDUCTION-POLICY.adoc, and a prose mention of a banned
# construct is not a hole. Block comments {- -} and (* *) and line comments
# -- and // are stripped before matching, with line numbers preserved.
# ---------------------------------------------------------------------------
scan_escape_hatches() {
  # $1 = file. Prints "line:token:text" for each real hit.
  local file="$1" stripped
  stripped="$(awk '
    BEGIN { block = 0 }
    {
      line = $0; out = ""; i = 1; n = length(line)
      while (i <= n) {
        two = substr(line, i, 2)
        if (block == 1) {
          if (two == "-}" || two == "*)") { block = 0; i += 2 } else { i += 1 }
          continue
        }
        if (two == "--" || two == "//") { break }
        if (two == "{-" || two == "(*") { block = 1; i += 2; continue }
        out = out substr(line, i, 1); i += 1
      }
      print out
    }' "$file")"
  # Hard bans: no status in PROOF-POLICY §5 can be carried by these.
  printf '%s\n' "$stripped" \
    | grep -nE '\b(believe_me|assert_total|postulate|sorry|admit|Admitted|unsafeCoerce)\b|\bObj[.]magic\b|\bsorryAx\b' \
    || true
}

# Declared axioms are different from escape hatches: PROOF-POLICY §5 allows
# `proven-with-postulates` when the axioms are named and allowed by
# TRUSTED-BASE-REDUCTION-POLICY. Collect them so the ledger can be cross-checked.
scan_declared_axioms() {
  local file="$1"
  case "$file" in
    *.v) grep -nE '^[[:space:]]*(Axiom|Parameter|Conjecture)[[:space:]]' "$file" || true ;;
    *.lean) grep -nE '^[[:space:]]*axiom[[:space:]]' "$file" || true ;;
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

echo "=== Proof ledger gate ==="
echo "ledger:   $LEDGER"
echo "policy:   standards/3-practice/PROOF-POLICY.adoc"
echo "grades:   mathesis/estate-mathematical-architecture §5-§6"
echo ""

# Closed vocabulary, verbatim from PROOF-POLICY §5 (canonical lowercase tokens).
VOCAB='["argued","open","proven","proven-with-postulates","tested-only"]'
# Prover families, from mathesis §5 (the Grade 2ii diversity rule).
FAMILIES='{"agda":"dtt","rocq":"dtt","lean4":"dtt","idris2":"dtt","isabelle":"hol","tla+":"state-machine","smt":"smt"}'

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
  [ .theorems[] | (.source.status // "<missing>"), (.legs[]?.status // "<missing>") ][]
  | select(. as $s | $vocab | index($s) | not)' "$LEDGER" | sort -u)

while IFS= read -r bad; do
  [ -n "$bad" ] && fail "theorem kind must be 'theory' or 'engineering' (PROOF-POLICY §1): '${bad}'"
done < <(jq -r '[.theorems[].kind // "<missing>"][] | select(. != "theory" and . != "engineering")' "$LEDGER" | sort -u)

while IFS= read -r dup; do
  [ -n "$dup" ] && fail "duplicate theorem id in ledger: '${dup}'"
done < <(jq -r '[.theorems[].id] | group_by(.)[] | select(length > 1) | .[0]' "$LEDGER")

while IFS= read -r bad; do
  [ -n "$bad" ] && fail "grade must be one of 3, 2i, 2ii, 1 (mathesis §5): '${bad}'"
done < <(jq -r '[.theorems[].grade // "<missing>" | tostring][] | select(. != "3" and . != "2i" and . != "2ii" and . != "1")' "$LEDGER" | sort -u)

# --- 3. per-theorem: legs, grades, claims ------------------------------------
# Emitted as TSV so bash can drive the filesystem checks.
jq -r '
  .theorems[] |
  [ .id,
    .kind,
    (.grade | tostring),
    ([.legs[]?.prover] | join(",")),
    ([.legs[]? | select(.status != "open")] | length),
    ([.legs[]? | select(.status == "proven" or .status == "proven-with-postulates")] | length)
  ] | @tsv' "$LEDGER" > /tmp/proof-ledger-rows.$$.tsv
trap 'rm -f /tmp/proof-ledger-rows.$$.tsv' EXIT

declare -A THEOREM_PROVEN=()
while IFS=$'\t' read -r tid kind grade provers claimed proven; do
  [ -z "$tid" ] && continue
  THEOREM_PROVEN["$tid"]="$proven"

  # PROOF-POLICY §1/§2: theory is Agda, rechecked in Rocq AND Lean.
  if [ "$kind" = "theory" ]; then
    for required in rocq lean4; do
      case ",$provers," in
        *",$required,"*) ;;
        *) fail "$tid: theory theorem is missing the '$required' recheck leg required by PROOF-POLICY §2 (legs: ${provers:-none})" ;;
      esac
    done
  fi

  case "$grade" in
    3)
      if [ "$proven" -gt 0 ]; then
        fail "$tid: grade 3 claims no translated leg, but $proven leg(s) are recorded proven (mathesis §5)"
      fi
      ;;
    2i)
      if [ "$proven" -ne 1 ]; then
        fail "$tid: grade 2i requires exactly one proven recheck leg, ledger records $proven (mathesis §5)"
      fi
      ;;
    2ii)
      if [ "$proven" -lt 2 ]; then
        fail "$tid: grade 2ii requires two proven legs, ledger records $proven (mathesis §5)"
      fi
      non_dtt="$(jq -r --argjson fam "$FAMILIES" --arg id "$tid" '
        [ .theorems[] | select(.id == $id) | .legs[]?
          | select(.status == "proven" or .status == "proven-with-postulates")
          | select($fam[.prover // ""] != null and $fam[.prover] != "dtt") ] | length' "$LEDGER")"
      if [ "${non_dtt:-0}" -lt 1 ]; then
        fail "$tid: grade 2ii needs one proven leg outside the DTT/CIC family (mathesis §5 — Agda, Rocq and Lean are the same family); none recorded"
      fi
      ;;
    1)
      api="$(jq -r --arg id "$tid" '
        [ .theorems[] | select(.id == $id) | .legs[]?
          | select(.status == "proven" or .status == "proven-with-postulates")
          | .api_receipt.api // empty ] | length' "$LEDGER")"
      if [ "${api:-0}" -lt 1 ]; then
        fail "$tid: grade 1 requires a verified-checker API receipt (AXLE, coq-lsp, isabelle-server — mathesis §5); none recorded"
      fi
      ;;
  esac

  if [ "$claimed" -gt 0 ]; then
    GAPS+=("$tid: $claimed leg(s) carry a non-open status and MUST compile in this lane")
  fi
done < /tmp/proof-ledger-rows.$$.tsv

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

while IFS=$'\t' read -r tid sprover sstatus rec_file_opts rec_cli rec_effective files_csv anchor_ids escape_evidence; do
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

  # (b) every source file must exist
  IFS=',' read -r -a src_files <<< "$files_csv"
  for f in "${src_files[@]}"; do
    [ -z "$f" ] && continue
    [ -f "$f" ] || fail "$tid: source file recorded but missing on disk: $f"
  done

  # (c) flags: what the instrument passes, what the files declare, and the
  # union the ledger claims must agree. Drift here silently changes what a
  # Grade 3 claim means.
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

  # (d) mathesis §5 names the Grade 3 configurations parenthetically
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

  # (e) the statement must rest on named declarations that exist. A grade
  # anchored to a file rather than a theorem is the "proof inflation" mathesis
  # §11 rejects.
  if [ -z "${anchor_ids// }" ]; then
    fail "$tid: no .statement_anchor — a grade must point at the named declarations that carry the statement, not at a file"
  else
    IFS=',' read -r -a anchors <<< "$anchor_ids"
    for a in "${anchors[@]}"; do
      [ -z "${a// }" ] && continue
      hit=0
      for f in "${src_files[@]}"; do
        [ -f "$f" ] || continue
        grep -qE "^[[:space:]]*${a//./\\.}[[:space:]]*:" "$f" && hit=1
      done
      [ "$hit" -eq 1 ] || fail "$tid: statement anchor '$a' is not declared in any recorded source file (looked in: $files_csv)"
    done
  fi

  # (e2) PROOF-POLICY §2 needs a statement comparison between the Agda source
  # and any recheck leg. That is impossible if the Agda statement is only prose,
  # so each recorded declaration's TYPE must still be in the file, whitespace-
  # normalised. When the Agda statement moves, this record has to move with it.
  while IFS=$'\t' read -r decl_name decl_type; do
    [ -z "${decl_name// }" ] && continue
    if [ -z "${decl_type// }" ]; then
      fail "$tid: statement_formal.$decl_name records no type — a recheck leg cannot be compared against it"
      continue
    fi
    norm_type="$(printf '%s' "$decl_type" | tr -s '[:space:]' ' ' | sed 's/^ *//; s/ *$//')"
    found=0
    for f in "${src_files[@]}"; do
      [ -f "$f" ] || continue
      norm_file="$(tr -s '[:space:]' ' ' < "$f")"
      case "$norm_file" in
        *"$norm_type"*) found=1 ;;
      esac
    done
    if [ "$found" -eq 0 ]; then
      fail "$tid: statement drifted — statement_formal.$decl_name records the type
     '$norm_type'
     which no recorded source file contains any more. If the Agda statement
     changed, re-record it here (and re-check any leg that was compared against
     it) — PROOF-POLICY §2's statement comparison is void otherwise."
    fi
  done < <(jq -r --arg id "$tid" '
    .theorems[] | select(.id == $id) | .statement_formal.declarations[]? |
    [ (.name // ""), (.type // "") ] | @tsv' "$LEDGER")

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
  ] | @tsv' "$LEDGER")

# --- 3c. Superseded / Regressed (mathesis §6) --------------------------------
# §6 requires a proof's history to record when it is superseded or regresses.
# Two rules make that real rather than decorative:
#   * every history entry is well formed (date, target, from, to, evidence);
#   * the LAST entry for a target must equal that target's current value — so a
#     downgrade cannot be quietly applied, and a record cannot be quietly
#     dropped. A transition to a weaker state must also carry a reason.
GRADE_STRENGTH='{"1":4,"2ii":3,"2i":2,"3":1}'
while IFS=$'\t' read -r tid target from to date evidence reason; do
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
  [ $id, (.target // ""), (.from // ""), (.to // ""), (.date // ""), (.evidence // ""), (.reason // "") ] | @tsv' "$LEDGER")

# the last entry for each target must be the current value
while IFS=$'\t' read -r tid target last_to; do
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
  | [ $id, (.target // ""), (.to // "") ] | @tsv' "$LEDGER")

# --- 4. every non-open claim must be backed by artifact + MANIFEST + route ---
while IFS=$'\t' read -r tid prover status artifact route compared axioms reproof; do
  [ -z "$tid" ] && continue
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
  if [ -n "$mdir" ]; then
    if [ ! -f "$mdir/MANIFEST" ]; then
      fail "$tid/$prover: $mdir/MANIFEST is missing, so $artifact cannot be compiled by the lane"
    elif ! grep -vE '^[[:space:]]*(#|$)' "$mdir/MANIFEST" | grep -qF "|$(basename "$artifact")|"; then
      fail "$tid/$prover: $artifact is not listed in $mdir/MANIFEST (unlisted witness)"
    fi
  fi

  # PROOF-POLICY §2.3: record the route; §2.1: without a statement comparison
  # the leg is ASSUMED (argued), not PROVEN.
  case "$route" in
    transported|re-proved) ;;
    *) fail "$tid/$prover: status '$status' requires route 'transported' or 're-proved' (PROOF-POLICY §2.3), got '${route}'" ;;
  esac
  if [ "$route" = "re-proved" ] && { [ -z "$reproof" ] || [ "$reproof" = "null" ]; }; then
    fail "$tid/$prover: route 're-proved' requires a reproof_reason (PROOF-POLICY §2.2)"
  fi
  if [ "$status" = "proven" ] || [ "$status" = "proven-with-postulates" ]; then
    case "$compared" in
      ""|null|none)
        fail "$tid/$prover: '$status' requires a statement comparison (PROOF-POLICY §2.1); without it the leg is 'argued'" ;;
    esac
  fi

  # §5: axioms are named, and only proven-with-postulates may have any.
  axiom_count="$(jq -r --arg id "$tid" --arg p "$prover" '
    [ .theorems[] | select(.id == $id) | .legs[]? | select(.prover == $p)
      | (.axioms // []) | length ] | .[0] // -1' "$LEDGER")"
  if [ "${axiom_count:--1}" -lt 0 ]; then
    fail "$tid/$prover: 'axioms' must be recorded as a list (empty when none) — mathesis §6 axiom tracking"
  elif [ "$status" = "proven" ] && [ "$axiom_count" -ne 0 ]; then
    fail "$tid/$prover: status 'proven' but $axiom_count axiom(s) recorded; that is 'proven-with-postulates' (§5)"
  elif [ "$status" = "proven-with-postulates" ] && [ "$axiom_count" -eq 0 ]; then
    fail "$tid/$prover: status 'proven-with-postulates' with an empty axiom list (§5: list the axioms)"
  fi

  # §2: no Mathlib. A proof that needs a large external library is a
  # dependency, not a proof the estate owns.
  if [ "$prover" = "lean4" ] && grep -qE '^[[:space:]]*import[[:space:]]+Mathlib' "$artifact"; then
    fail "$tid/$prover: $artifact imports Mathlib, which PROOF-POLICY §2 forbids"
  fi
done < <(jq -r '
  .theorems[] as $t | $t.legs[]? |
  [ $t.id, .prover, (.status // ""), (.artifact // ""), (.route // ""),
    (if (.statement_compared // null) == null then "" else (.statement_compared | tostring) end),
    (if (.axioms // null) == null then "" else "recorded" end),
    (.reproof_reason // "") ] | @tsv' "$LEDGER")

# --- 5. source legs: files, receipts, safety flags ---------------------------
while IFS=$'\t' read -r tid status files; do
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
    read -r ekind ecommit edate erun < <(jq -r --arg id "$tid" '
      .theorems[] | select(.id == $id) | .source.evidence? |
      [ (.kind // ""), (.commit // ""), (.date // ""), (.run // "") ] | @tsv' "$LEDGER")
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
done < <(jq -r '.theorems[] | [ .id, (.source.status // ""), ((.source.files // []) | join(",")) ] | @tsv' "$LEDGER")

# Agda safety flags stay in force (this repository's PROOF-NEEDS.adoc).
while IFS= read -r f; do
  [ -z "$f" ] && continue
  grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--safe' "$f" \
    || fail "missing safety flag: $f does not declare --safe in its OPTIONS pragma"
  grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--without-K' "$f" \
    || fail "missing safety flag: $f does not declare --without-K in its OPTIONS pragma"
done < <(jq -r '.theorems[].source.files[]? | select(endswith(".agda"))' "$LEDGER" | sort -u)

# --- 6. escape hatches + declared axioms in every proof/witness source -------
declare -A DECLARED_AXIOMS=()
while IFS=$'\t' read -r tid _p axioms; do
  [ -z "$tid" ] && continue
  case "$axioms" in
    ""|null) continue ;;
  esac
  IFS=',' read -r -a ax_list <<<"$axioms"
  for a in "${ax_list[@]}"; do
    [ -n "$a" ] && DECLARED_AXIOMS["$a"]=1
  done
done < <(jq -r '.theorems[] as $t | $t.legs[]? | [ $t.id, .prover, ((.axioms // []) | join(",")) ] | @tsv' "$LEDGER")

scan_one() {
  local f="$1" hits
  hits="$(scan_escape_hatches "$f")"
  if [ -n "$hits" ]; then
    fail "escape hatch in $f:
$(printf '%s\n' "$hits" | sed 's/^/     line /')"
  fi
  local ax
  ax="$(scan_declared_axioms "$f")"
  if [ -n "$ax" ]; then
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      name="$(printf '%s\n' "$line" | sed -E 's/^[0-9]+:[[:space:]]*(Axiom|Parameter|Conjecture|axiom)[[:space:]]+([A-Za-z0-9_′]+).*/\2/')"
      if [ -z "${DECLARED_AXIOMS[$name]:-}" ]; then
        fail "undeclared axiom in $f:$line — PROOF-POLICY §5 requires every axiom to be named in the ledger (proven-with-postulates)"
      fi
    done <<<"$ax"
  fi
}

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  PROOF_FILES="$(git ls-files -- "$PROOFS_DIR" | grep -E '\.(agda|lagda|idr|v|lean|tla)$' | sort)"
else
  PROOF_FILES="$(find "$PROOFS_DIR" -type f \( -name '*.agda' -o -name '*.idr' -o -name '*.v' -o -name '*.lean' -o -name '*.tla' \) 2>/dev/null | sort)"
fi
scanned=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  scanned=$((scanned + 1))
  scan_one "$f"
done <<<"$PROOF_FILES"

if [ "$scanned" -eq 0 ]; then
  fail "zero-work: no proof source or witness was scanned under $PROOFS_DIR"
fi

# --- 7. witnesses on disk must be claimed in the ledger ----------------------
# Enumerated the same way as section 6: `git ls-files` inside a work tree, a
# plain `find` otherwise. Using git alone here would make the check silently
# vacuous in an exported tree (no .git) — a null check that reports OK, which is
# the exact failure mode the estate instrument exists to prevent.
list_witnesses() {  # $1 = prover dir under $PROOFS_DIR, $2 = extension
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files -- "$PROOFS_DIR/$1" 2>/dev/null | grep -E "\.$2\$" | sort
  else
    find "$PROOFS_DIR/$1" -type f -name "*.$2" 2>/dev/null | sort
  fi
}
LEDGER_ARTIFACTS="$(jq -r '.theorems[].legs[]?.artifact // empty' "$LEDGER" | sort -u)"
for dir in coq lean4; do
  ext=v; [ "$dir" = "lean4" ] && ext=lean
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if ! printf '%s\n' "$LEDGER_ARTIFACTS" | grep -Fxq -- "$f"; then
      fail "witness on disk is not claimed in the ledger: $f
     Add a leg row with artifact '$f' (route, axioms, statement comparison) — an
     unclaimed witness is exactly the silent-drift case mathesis §11 rejects."
    fi
  done < <(list_witnesses "$dir" "$ext")
done

# --- 8. cross-project registry: manifest <-> boundary allowlist <-> disk -----
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
while IFS=$'\t' read -r tid prover status blocker; do
  [ -z "$tid" ] && continue
  [ "$status" = "open" ] || continue
  GAPS+=("$tid: $prover leg is OPEN${blocker:+ — $blocker}")
done < <(jq -r '.theorems[] as $t | $t.legs[]? | select(.status == "open") | [ $t.id, .prover, .status, (.blocker // "") ] | @tsv' "$LEDGER")

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

if [ -n "$RECEIPT" ]; then
  mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null || true
  {
    echo "proof-ledger receipt"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
    echo "runner: ${RUNNER_NAME:-local}/${RUNNER_OS:-$(uname -s)}"
    echo "status: $status"
    echo "policy: standards/3-practice/PROOF-POLICY.adoc"
    echo "grade-model: mathesis/estate-mathematical-architecture §5-§6"
    echo "theorems: $theorem_count"
    echo "proof-sources-scanned: $scanned"
    echo "proven-recheck-legs: $proven_legs"
    echo "ledger-sha256: $(sha256sum "$LEDGER" | cut -d' ' -f1)"
    echo "gaps:"
    if [ "${#GAPS[@]}" -eq 0 ]; then echo "  (none)"; else printf '  - %s\n' "${GAPS[@]}"; fi
    if [ "${#FAILS[@]}" -gt 0 ]; then
      echo "failures:"
      printf '  - %s\n' "${FAILS[@]}"
    fi
  } >"$RECEIPT"
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
