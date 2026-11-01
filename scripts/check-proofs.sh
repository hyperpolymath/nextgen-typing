#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# check-proofs.sh <prover> [--root PATH] [--ledger PATH] [--receipt PATH]
#   prover in: idris2 | lean4 | agda | coq
#
# Single source of truth for compiling <prover> proofs AND, for every gated
# Rocq/Lean recheck witness, querying kernel-level assumptions against the
# owning leg's recorded `axioms` list in verification/proofs/LEDGER.json
# (nextgen-typing#131, PROOF-POLICY §2 / §5 / §6 / §7, mathesis §5-§6).
#
# Why compilation alone is insufficient:
#   - `coqc` exits 0 on `Admitted`, on local `Axiom`/`Parameter` declarations,
#     and on clean proofs that `Require Import` axioms from another module
#     (such as `Coq.Logic.Classical_Prop.classic`).
#   - `lean` exits 0 on `sorry`, on local `axiom` declarations, and on proofs
#     whose imported dependencies use `Classical.choice` or `sorryAx`.
#   - Single-file lexical scanning (`proof-scan-dangerous.sh`) catches tokens
#     written inside the witness file itself, NOT assumptions imported across a
#     module boundary or drawn from a standard library.
#
# Therefore, after compiling every gated Rocq or Lean module in an isolated
# scratch tree (leaving no `.vo`/`.glob`/`.olean` build artifacts in the working
# tree):
#   * Rocq (`coq`):
#       1. Runs `coqchk -Q . "" -silent -o <module>` on the compiled `.vo`,
#          verifying a predicative `Set`, `<none>` for `type-in-type`, unsafe
#          `(co)fixpoints`, and assumed positivity, and comparing `* Axioms:`
#          against the ledger's `axioms` list for the claiming leg(s).
#       2. Generates and compiles a probe that `Require`s `<module>` and runs
#          `Print Assumptions <module>.<decl>.` for every recorded target
#          declaration, failing closed unless output is `Closed under the
#          global context` or `Axioms:` matching the ledger entry.
#   * Lean 4 (`lean4`):
#       1. Compiles with `-R <work_root> -o <module>.olean` (preserving
#          `lean --print-libdir` on `LEAN_PATH`).
#       2. Generates and runs a probe that `import`s `<module>` and executes
#          `#print axioms <decl>` for every recorded target declaration,
#          failing unconditionally on `sorryAx` and on any unrecorded or stale
#          ledger axiom.
#   * Verbatim kernel query output is appended to `--receipt` whenever supplied.
#
# Exit: 0 = every gated module compiles, passes kernel assumption checks, every
#           quarantined module still fails, and every proof on disk is listed;
#       1 = compilation, coverage, or assumption failure;
#       2 = CLI misuse.

set -euo pipefail

usage() {
  echo "usage: $(basename "$0") <idris2|lean4|agda|coq> [--root PATH] [--ledger PATH] [--receipt PATH]" >&2
  exit 2
}

PROVER="${1:-}"
case "$PROVER" in
  idris2|lean4|agda|coq) shift ;;
  *) usage ;;
esac

CALLER_PWD="$PWD"
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT_ARG=""
LEDGER_ARG=""
RECEIPT_ARG=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --root)
      [[ "$#" -ge 2 ]] || usage
      ROOT_ARG="$2"
      shift 2
      ;;
    --root=*)
      ROOT_ARG="${1#--root=}"
      shift
      ;;
    --ledger)
      [[ "$#" -ge 2 ]] || usage
      LEDGER_ARG="$2"
      shift 2
      ;;
    --ledger=*)
      LEDGER_ARG="${1#--ledger=}"
      shift
      ;;
    --receipt)
      [[ "$#" -ge 2 ]] || usage
      RECEIPT_ARG="$2"
      shift 2
      ;;
    --receipt=*)
      RECEIPT_ARG="${1#--receipt=}"
      shift
      ;;
    -h|--help)
      sed -n '2,47p' "$0"
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage
      ;;
  esac
done

resolve_caller_path() {
  local p="$1"
  if [[ "$p" == /* ]]; then
    printf '%s\n' "$p"
  else
    printf '%s/%s\n' "$CALLER_PWD" "$p"
  fi
}

if [[ -n "$ROOT_ARG" ]]; then
  ROOT="$(cd "$(resolve_caller_path "$ROOT_ARG")" && pwd)"
else
  ROOT="$SCRIPT_ROOT"
fi
cd "$ROOT"

PROOF_DIR="verification/proofs/$PROVER"
MANIFEST_FILE="$PROOF_DIR/MANIFEST"

if [[ -n "$LEDGER_ARG" ]]; then
  LEDGER="$(resolve_caller_path "$LEDGER_ARG")"
else
  LEDGER="$ROOT/verification/proofs/LEDGER.json"
fi

RECEIPT=""
if [[ -n "$RECEIPT_ARG" ]]; then
  RECEIPT="$(resolve_caller_path "$RECEIPT_ARG")"
  if ! mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null; then
    echo "FAIL: cannot create receipt directory for $RECEIPT" >&2
    exit 1
  fi
fi

# --- per-prover configuration -------------------------------------------------
case "$PROVER" in
  idris2) CMD=idris2; EXT=idr;  ERROR_RE='^Error:' ;;
  lean4)  CMD=lean;   EXT=lean; ERROR_RE='error:'  ;;
  agda)   CMD=agda;   EXT=agda; ERROR_RE=''        ;;
  coq)    CMD=coqc;   EXT=v;    ERROR_RE=''        ;;
esac

RECEIPT_SECTIONS=()
append_receipt_section() {
  RECEIPT_SECTIONS+=("$1")
}

write_receipt() {
  local status="$1" gated_cnt="$2" quar_cnt="$3" note_line="${4:-}"
  [[ -n "$RECEIPT" ]] || return 0
  local ledger_sha="unavailable"
  if [[ -f "$LEDGER" ]]; then
    ledger_sha="$(sha256sum "$LEDGER" | cut -d' ' -f1)"
  fi
  {
    echo "proof-witness receipt ($PROVER)"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
    echo "prover: $PROVER"
    echo "status: $status"
    echo "manifest: $MANIFEST_FILE"
    echo "ledger: ${LEDGER#"$ROOT"/}"
    echo "ledger-sha256: $ledger_sha"
    echo "gated-modules: $gated_cnt"
    echo "quarantined-modules: $quar_cnt"
    if [[ -n "$note_line" ]]; then
      echo "note: $note_line"
    fi
    if [[ "${#RECEIPT_SECTIONS[@]}" -gt 0 ]]; then
      echo ""
      echo "=== verbatim kernel assumption queries ==="
      local sec
      for sec in "${RECEIPT_SECTIONS[@]}"; do
        printf '%s\n' "$sec"
      done
    fi
  } >"$RECEIPT" || {
    echo "FAIL: cannot write receipt $RECEIPT" >&2
    exit 1
  }
}

echo "=== $PROVER proof check ==="

# --- a repo with proofs but no MANIFEST is itself a failure -------------------
if [[ ! -f "$MANIFEST_FILE" ]]; then
  if [[ -d "$PROOF_DIR" ]] && [[ -n "$(find "$PROOF_DIR" -name "*.$EXT" 2>/dev/null)" ]]; then
    echo "FAIL: $PROOF_DIR contains .$EXT proofs but has no MANIFEST." >&2
    echo "      Create $MANIFEST_FILE listing each as 'gated' or 'quarantine'." >&2
    write_receipt "FAIL" 0 0 "missing MANIFEST for non-empty $PROOF_DIR"
    exit 1
  fi
  echo "no $PROOF_DIR/*.$EXT proofs and no MANIFEST — nothing to check."
  write_receipt "PASS (no-manifest)" 0 0 "no .$EXT proofs and no MANIFEST"
  exit 0
fi

# --- nothing to check is not the same as a missing toolchain -----------------
manifest_entries=0
if [[ -f "$MANIFEST_FILE" ]]; then
  while IFS='|' read -r mroot _mrel _mstatus _mnote; do
    [[ -z "${mroot// }" ]] && continue
    case "${mroot#"${mroot%%[![:space:]]*}"}" in \#*) continue ;; esac
    manifest_entries=$((manifest_entries + 1))
  done < "$MANIFEST_FILE"
fi
disk_proofs="$(find "$PROOF_DIR" -name "*.$EXT" -not -path '*/build/*' 2>/dev/null | head -1)"
if [[ "$manifest_entries" -eq 0 ]] && [[ -z "$disk_proofs" ]]; then
  echo "no $PROOF_DIR/*.$EXT proofs and no MANIFEST entries — nothing to check."
  write_receipt "PASS (no-modules)" 0 0 "0 gated modules in MANIFEST; no witness compiled or assumption-queried"
  exit 0
fi

# --- toolchain: absent means FAIL, never skip ---------------------------------
required_tools=("$CMD")
case "$PROVER" in
  coq)   required_tools+=(coqchk coqtop jq) ;;
  lean4) required_tools+=(jq) ;;
esac
for req_tool in "${required_tools[@]}"; do
  if ! command -v "$req_tool" >/dev/null 2>&1; then
    {
      echo "FAIL: '$req_tool' not found on PATH."
      echo
      echo "This is deliberately fatal.  A missing $PROVER verification tool must"
      echo "never report green on work it could not check.  Install '$req_tool',"
      echo "or run this in CI where the workflow installs the pinned toolchain."
    } >&2
    write_receipt "FAIL (missing-toolchain)" 0 0 "missing required tool: $req_tool"
    exit 1
  fi
done

TOOLCHAIN_LINE="$("$CMD" --version 2>/dev/null | head -1 || true)"
printf '%s\n' "$TOOLCHAIN_LINE"
if [[ "$PROVER" == "coq" ]]; then
  COQCHK_LINE="$(coqchk --version 2>&1 | head -1 || true)"
  append_receipt_section "toolchain: coqc=${TOOLCHAIN_LINE}; coqchk=${COQCHK_LINE}"
elif [[ "$PROVER" == "lean4" ]]; then
  LEAN_LIBDIR="$(lean --print-libdir 2>/dev/null || printf '%s/lib/lean' "$(lean --print-prefix)")"
  append_receipt_section "toolchain: lean=${TOOLCHAIN_LINE}"
elif [[ -n "$TOOLCHAIN_LINE" ]]; then
  append_receipt_section "toolchain: ${CMD}=${TOOLCHAIN_LINE}"
fi
echo

listed_tmp="$(mktemp)"
WORK_BASE="$(mktemp -d)"
trap 'rm -f "$listed_tmp"; rm -rf "$WORK_BASE"' EXIT

normalize_rel_path() {
  local root="${1%/}" rel="${2#./}"
  root="${root#./}"
  if [[ -z "$root" || "$root" == "." ]]; then
    printf '%s\n' "$rel"
  else
    printf '%s/%s\n' "$root" "$rel"
  fi
}

stage_source_root() {
  local root="${1%/}"
  root="${root#./}"
  [[ -z "$root" ]] && root="."
  local dest="$WORK_BASE/$root"
  if [[ ! -d "$dest" ]]; then
    mkdir -p "$dest"
    cp -a "$ROOT/$root/." "$dest/"
  fi
  printf '%s\n' "$dest"
}

LAST_OUT=""
check_one() {
  local root="$1" rel="$2" out rc work_root olean_rel olean_out
  set +e
  case "$PROVER" in
    idris2)
      out="$(cd "$ROOT/$root" && idris2 --check "$rel" 2>&1)"
      rc=$?
      ;;
    lean4)
      work_root="$(stage_source_root "$root")"
      olean_rel="${rel#./}"
      olean_out="$work_root/${olean_rel%.lean}.olean"
      mkdir -p "$(dirname "$olean_out")"
      out="$(cd "$work_root" && LEAN_PATH="$work_root:$LEAN_LIBDIR${LEAN_PATH:+:$LEAN_PATH}" lean -R "$work_root" -o "$olean_out" "$work_root/$olean_rel" 2>&1)"
      rc=$?
      ;;
    agda)
      out="$(cd "$ROOT/$root" && agda --safe --without-K --cubical-compatible "$rel" 2>&1)"
      rc=$?
      ;;
    coq)
      work_root="$(stage_source_root "$root")"
      out="$(cd "$work_root" && coqc -Q . "" "$rel" 2>&1)"
      rc=$?
      ;;
  esac
  set -e
  if [[ "$rc" -eq 0 ]] && { [[ -z "$ERROR_RE" ]] || ! grep -qE "$ERROR_RE" <<<"$out"; }; then
    LAST_OUT=""
    return 0
  fi
  LAST_OUT="$out"
  return 1
}

is_valid_ident() {
  local ident="$1"
  [[ "$ident" =~ ^[A-Za-z_][A-Za-z0-9_\']*(\.[A-Za-z_][A-Za-z0-9_\']*)*$ ]]
}

array_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Match a kernel-reported Coq axiom `<mod_path>.<short>` or external `<pkg>.<ax>`
# against the owning leg's recorded `.axioms` array. External axioms must match
# verbatim; module-local `Axiom`/`Parameter`/`Conjecture` constants may match
# either `<mod_path>.<short>` or `<short>`, provided `<short>` is actually a
# declared axiom in the file rather than a `Theorem ... Admitted`.
coq_axiom_allowed() {
  local ax="$1" mod_path="$2" src_file="$3"
  shift 3
  local allowed=("$@")
  if [[ "${#allowed[@]}" -gt 0 ]] && array_contains "$ax" "${allowed[@]}"; then
    return 0
  fi
  local prefix="${mod_path}."
  if [[ "$ax" == "${prefix}"* ]]; then
    local short="${ax#"$prefix"}"
    if grep -qE "^[[:space:]]*(Axiom|Parameter|Conjecture)[[:space:]]+${short//./\\.}[^A-Za-z0-9_']" "$src_file" 2>/dev/null; then
      if [[ "${#allowed[@]}" -gt 0 ]] && array_contains "$short" "${allowed[@]}"; then
        return 0
      fi
    fi
  fi
  return 1
}

ASSUMPTION_ERR=""

verify_ledger_ready() {
  local full_rel="$1"
  if [[ ! -f "$LEDGER" ]]; then
    ASSUMPTION_ERR="assumption check failed for $full_rel: ledger not found at $LEDGER"
    return 1
  fi
  if ! jq -e . "$LEDGER" >/dev/null 2>&1; then
    ASSUMPTION_ERR="assumption check failed for $full_rel: ledger is not valid JSON ($LEDGER)"
    return 1
  fi
  return 0
}

# Emit matching non-open legs for ($1 = prover_kind: coq|lean4, $2 = full_rel).
# Output lines use US (\x1f): role(primary|support), tid, status, axioms_json, decls_json, bad_axioms_flag
query_claiming_legs() {
  local pkind="$1" full_rel="$2"
  jq -r --arg kind "$pkind" --arg path "$full_rel" '
    def match_prover($p):
      if $kind == "coq" then ($p == "rocq" or $p == "coq")
      else ($p == "lean4" or $p == "lean")
      end;
    def target_decls($t; $leg):
      if ($leg.declarations // null) != null then
        if ($leg.declarations | type) == "array" then
          [ $leg.declarations[] | if type == "object" then (.name // "") else tostring end ]
        else
          ["<invalid-declarations-type>"]
        end
      elif (($t.statement_formal.declarations // []) | length) > 0 then
        [ $t.statement_formal.declarations[] | (.name // "") ]
      else
        [ ($t.statement_anchor // [])[] | tostring ]
      end;
    .theorems[] as $t
    | ($t.legs // [])[] as $leg
    | select($leg.waiver == null)
    | select(match_prover($leg.prover // ""))
    | select(($leg.status // "open") != "open")
    | (if ($leg.artifact // "") == $path then "primary"
       elif ((($leg.support_files // []) | type) == "array" and (($leg.support_files // []) | index($path)) != null) then "support"
       else "" end) as $role
    | select($role != "")
    | [
        $role,
        ($t.id // "<unnamed>"),
        ($leg.status // ""),
        (if (($leg.axioms // []) | type) == "array" then (($leg.axioms // []) | tojson) else "null" end),
        (target_decls($t; $leg) | tojson)
      ]
    | join("\u001f")
  ' "$LEDGER"
}

verify_coq_assumptions() {
  local root="$1" rel="$2" work_root="$3"
  local clean_rel="${rel#./}"
  local full_rel mod_path src_file
  full_rel="$(normalize_rel_path "$root" "$clean_rel")"
  mod_path="${clean_rel%.v}"
  mod_path="${mod_path//\//.}"
  src_file="$work_root/$clean_rel"

  verify_ledger_ready "$full_rel" || return 1

  local leg_rows=()
  local row
  while IFS= read -r row; do
    [[ -n "$row" ]] && leg_rows+=("$row")
  done < <(query_claiming_legs "coq" "$full_rel")

  if [[ "${#leg_rows[@]}" -eq 0 ]]; then
    ASSUMPTION_ERR="assumption check failed for $full_rel: gated in $MANIFEST_FILE, but no non-open Rocq leg in $LEDGER claims '$full_rel' (in .artifact or .support_files)"
    return 1
  fi

  # 1. Kernel checker over the compiled .vo (`coqchk -silent -o`).
  local coqchk_out coqchk_rc
  set +e
  coqchk_out="$(cd "$work_root" && coqchk -Q . "" -silent -o "$mod_path" 2>&1)"
  coqchk_rc=$?
  set -e

  append_receipt_section "--- [coqchk] $full_rel (module: $mod_path) ---
\$ coqchk -Q . \"\" -silent -o $mod_path
${coqchk_out}"

  if [[ "$coqchk_rc" -ne 0 ]] || ! grep -qF 'CONTEXT SUMMARY' <<<"$coqchk_out"; then
    ASSUMPTION_ERR="coqchk failed or emitted no CONTEXT SUMMARY for $full_rel (exit $coqchk_rc):
$coqchk_out"
    return 1
  fi
  if ! grep -qE '^\* Theory: Set is predicative[[:space:]]*$' <<<"$coqchk_out"; then
    ASSUMPTION_ERR="$full_rel: coqchk did not confirm predicative Set:
$coqchk_out"
    return 1
  fi
  if ! grep -qE '^\* Constants/Inductives relying on type-in-type:[[:space:]]*<none>[[:space:]]*$' <<<"$coqchk_out"; then
    ASSUMPTION_ERR="$full_rel: coqchk reported type-in-type reliance:
$coqchk_out"
    return 1
  fi
  if ! grep -qE '^\* Constants/Inductives relying on unsafe \(co\)fixpoints:[[:space:]]*<none>[[:space:]]*$' <<<"$coqchk_out"; then
    ASSUMPTION_ERR="$full_rel: coqchk reported unsafe (co)fixpoints:
$coqchk_out"
    return 1
  fi
  if ! grep -qE '^\* Inductives whose positivity is assumed:[[:space:]]*<none>[[:space:]]*$' <<<"$coqchk_out"; then
    ASSUMPTION_ERR="$full_rel: coqchk reported assumed inductive positivity:
$coqchk_out"
    return 1
  fi

  local coqchk_ax_raw coqchk_parse_rc
  set +e
  coqchk_ax_raw="$(awk '
    /^\* Axioms:[[:space:]]*<none>[[:space:]]*$/ { seen = 1; none = 1; next }
    /^\* Axioms:[[:space:]]*$/ { seen = 1; in_ax = 1; next }
    in_ax && /^\*/ { in_ax = 0 }
    in_ax && NF > 0 {
      line = $0
      sub(/^[[:space:]]+/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") { print line; count++ }
    }
    END {
      if (!seen) exit 2
      if (!none && count == 0) exit 3
    }
  ' <<<"$coqchk_out")"
  coqchk_parse_rc=$?
  set -e
  if [[ "$coqchk_parse_rc" -ne 0 ]]; then
    ASSUMPTION_ERR="$full_rel: could not parse '* Axioms:' block from coqchk output (code $coqchk_parse_rc):
$coqchk_out"
    return 1
  fi

  local coqchk_axioms=()
  local ax_line
  while IFS= read -r ax_line; do
    [[ -n "$ax_line" ]] && coqchk_axioms+=("$ax_line")
  done <<<"$coqchk_ax_raw"

  # 2. Validate against every claiming leg and run per-declaration Print Assumptions.
  local role tid leg_status axioms_json decls_json
  for row in "${leg_rows[@]}"; do
    IFS=$'\x1f' read -r role tid leg_status axioms_json decls_json <<<"$row"
    if [[ "$axioms_json" == "null" ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): leg .axioms must be a JSON array"
      return 1
    fi

    local allowed_axioms=()
    local a_entry
    while IFS= read -r a_entry; do
      [[ -n "$a_entry" ]] && allowed_axioms+=("$a_entry")
    done < <(jq -r '.[]' <<<"$axioms_json")

    if [[ "${#allowed_axioms[@]}" -gt 0 ]] && array_contains "sorryAx" "${allowed_axioms[@]}"; then
      ASSUMPTION_ERR="$full_rel ($tid): 'sorryAx' is never permitted in .axioms"
      return 1
    fi
    if [[ "$leg_status" == "proven" && "${#allowed_axioms[@]}" -gt 0 ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): status is 'proven' (zero axioms permitted) but .axioms lists: ${allowed_axioms[*]}"
      return 1
    fi
    if [[ "$leg_status" == "proven-with-postulates" && "${#allowed_axioms[@]}" -eq 0 ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): status is 'proven-with-postulates' but .axioms is empty"
      return 1
    fi

    local cax
    for cax in ${coqchk_axioms[@]+"${coqchk_axioms[@]}"}; do
      if ! coq_axiom_allowed "$cax" "$mod_path" "$src_file" ${allowed_axioms[@]+"${allowed_axioms[@]}"}; then
        ASSUMPTION_ERR="$full_rel ($tid): coqchk reported undeclared axiom '$cax' (ledger allows: [${allowed_axioms[*]:-none}])"
        return 1
      fi
    done

    if [[ "$role" == "primary" ]]; then
      local target_decls=()
      local d_entry
      while IFS= read -r d_entry; do
        [[ -n "$d_entry" ]] && target_decls+=("$d_entry")
      done < <(jq -r '.[]' <<<"$decls_json")

      if [[ "${#target_decls[@]}" -eq 0 ]]; then
        ASSUMPTION_ERR="$full_rel ($tid): no target declarations recorded in statement_formal.declarations or leg.declarations"
        return 1
      fi

      local seen_leg_axioms=()
      local decl qdecl probe_v probe_out probe_rc
      for decl in "${target_decls[@]}"; do
        if ! is_valid_ident "$decl"; then
          ASSUMPTION_ERR="$full_rel ($tid): declaration '$decl' is not a valid Rocq identifier — map Agda anchors to Rocq identifiers in legs[].declarations"
          return 1
        fi
        if [[ "$decl" == "${mod_path}."* ]]; then
          qdecl="$decl"
        else
          qdecl="${mod_path}.${decl}"
        fi
        probe_v="$work_root/__probe_assumptions.v"
        printf 'Set Printing Width 1000000.\nRequire %s.\nPrint Assumptions %s.\n' "$mod_path" "$qdecl" >"$probe_v"
        set +e
        probe_out="$(cd "$work_root" && coqc -Q . "" __probe_assumptions.v 2>&1)"
        probe_rc=$?
        set -e
        rm -f "$work_root"/__probe_assumptions.*

        append_receipt_section "--- [Print Assumptions] $full_rel ($tid :: $qdecl) ---
recorded-axioms: ${axioms_json}
\$ Print Assumptions ${qdecl}.
${probe_out}"

        if [[ "$probe_rc" -ne 0 ]] || grep -qE '^Error:' <<<"$probe_out"; then
          ASSUMPTION_ERR="$full_rel ($tid): Print Assumptions failed for '$qdecl' (exit $probe_rc):
$probe_out"
          return 1
        fi
        if grep -qE '^(Section Variables|Type Variables|Relies on):' <<<"$probe_out"; then
          ASSUMPTION_ERR="$full_rel ($tid): '$qdecl' relies on unclosed section/type variables or unsafe flags:
$probe_out"
          return 1
        fi
        if grep -qE '^Closed under the global context[[:space:]]*$' <<<"$probe_out" \
           && ! grep -qE '^Axioms:' <<<"$probe_out"; then
          continue
        fi
        if grep -qE '^Axioms:[[:space:]]*$' <<<"$probe_out"; then
          local decl_ax_raw
          decl_ax_raw="$(awk '
            /^Axioms:[[:space:]]*$/ { in_ax = 1; next }
            in_ax && /^[A-Za-z_][A-Za-z0-9_\x27.]*[[:space:]]*:/ {
              line = $0
              sub(/[[:space:]]*:.*$/, "", line)
              print line
            }
          ' <<<"$probe_out")"
          if [[ -z "${decl_ax_raw//[[:space:]]/}" ]]; then
            ASSUMPTION_ERR="$full_rel ($tid): Print Assumptions printed 'Axioms:' for '$qdecl' but no axiom names could be parsed:
$probe_out"
            return 1
          fi
          local dax
          while IFS= read -r dax; do
            [[ -z "$dax" ]] && continue
            if ! coq_axiom_allowed "$dax" "$mod_path" "$src_file" ${allowed_axioms[@]+"${allowed_axioms[@]}"}; then
              ASSUMPTION_ERR="$full_rel ($tid): '$qdecl' depends on undeclared axiom '$dax' (ledger allows: [${allowed_axioms[*]:-none}])"
              return 1
            fi
            seen_leg_axioms+=("$dax")
          done <<<"$decl_ax_raw"
        else
          ASSUMPTION_ERR="$full_rel ($tid): unexpected Print Assumptions output for '$qdecl':
$probe_out"
          return 1
        fi
      done

      # Every axiom listed in .axioms on the primary leg must actually be used
      # by the witness (either on a recorded declaration or in the module's coqchk
      # summary), preventing stale or padded axiom lists.
      local lax matched_lax obs
      for lax in ${allowed_axioms[@]+"${allowed_axioms[@]}"}; do
        matched_lax=0
        for obs in ${seen_leg_axioms[@]+"${seen_leg_axioms[@]}"} ${coqchk_axioms[@]+"${coqchk_axioms[@]}"}; do
          [[ -z "$obs" ]] && continue
          if [[ "$obs" == "$lax" || "$obs" == "${mod_path}.${lax}" ]]; then
            matched_lax=1
            break
          fi
        done
        if [[ "$matched_lax" -eq 0 ]]; then
          ASSUMPTION_ERR="$full_rel ($tid): ledger .axioms lists '$lax', but neither Print Assumptions nor coqchk reported '$lax' — remove stale axioms (or promote status to 'proven' if axiom-free)"
          return 1
        fi
      done
    fi
  done

  return 0
}

verify_lean_assumptions() {
  local root="$1" rel="$2" work_root="$3"
  local clean_rel="${rel#./}"
  local full_rel mod_path
  full_rel="$(normalize_rel_path "$root" "$clean_rel")"
  mod_path="${clean_rel%.lean}"
  mod_path="${mod_path//\//.}"

  verify_ledger_ready "$full_rel" || return 1

  local leg_rows=()
  local row
  while IFS= read -r row; do
    [[ -n "$row" ]] && leg_rows+=("$row")
  done < <(query_claiming_legs "lean4" "$full_rel")

  if [[ "${#leg_rows[@]}" -eq 0 ]]; then
    ASSUMPTION_ERR="assumption check failed for $full_rel: gated in $MANIFEST_FILE, but no non-open Lean leg in $LEDGER claims '$full_rel' (in .artifact or .support_files)"
    return 1
  fi

  local role tid leg_status axioms_json decls_json
  for row in "${leg_rows[@]}"; do
    IFS=$'\x1f' read -r role tid leg_status axioms_json decls_json <<<"$row"
    if [[ "$axioms_json" == "null" ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): leg .axioms must be a JSON array"
      return 1
    fi

    local allowed_axioms=()
    local a_entry
    while IFS= read -r a_entry; do
      [[ -n "$a_entry" ]] && allowed_axioms+=("$a_entry")
    done < <(jq -r '.[]' <<<"$axioms_json")

    if [[ "${#allowed_axioms[@]}" -gt 0 ]] && array_contains "sorryAx" "${allowed_axioms[@]}"; then
      ASSUMPTION_ERR="$full_rel ($tid): 'sorryAx' is an incomplete-proof marker and is never permitted in .axioms"
      return 1
    fi
    if [[ "$leg_status" == "proven" && "${#allowed_axioms[@]}" -gt 0 ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): status is 'proven' (zero axioms permitted) but .axioms lists: ${allowed_axioms[*]}"
      return 1
    fi
    if [[ "$leg_status" == "proven-with-postulates" && "${#allowed_axioms[@]}" -eq 0 ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): status is 'proven-with-postulates' but .axioms is empty"
      return 1
    fi

    if [[ "$role" == "support" ]]; then
      # Support modules are compiled to .olean above; check that simply importing
      # the module succeeds cleanly, while the primary artifact probes the
      # recorded declarations' transitive axiom closure (which includes every
      # imported support module).
      local sup_probe="$work_root/__AssumptionsSupportProbe.lean"
      local sup_out sup_rc
      printf 'import %s\n' "$mod_path" >"$sup_probe"
      set +e
      sup_out="$(cd "$work_root" && LEAN_PATH="$work_root:$LEAN_LIBDIR${LEAN_PATH:+:$LEAN_PATH}" lean "$sup_probe" 2>&1)"
      sup_rc=$?
      set -e
      rm -f "$sup_probe"
      append_receipt_section "--- [Lean support import] $full_rel ($tid :: $mod_path) ---
\$ import ${mod_path}
${sup_out:-<clean>}"
      if [[ "$sup_rc" -ne 0 ]] || grep -qE 'error:' <<<"$sup_out"; then
        ASSUMPTION_ERR="$full_rel ($tid): importing support module '$mod_path' failed (exit $sup_rc):
$sup_out"
        return 1
      fi
      continue
    fi

    local target_decls=()
    local d_entry
    while IFS= read -r d_entry; do
      [[ -n "$d_entry" ]] && target_decls+=("$d_entry")
    done < <(jq -r '.[]' <<<"$decls_json")

    if [[ "${#target_decls[@]}" -eq 0 ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): no target declarations recorded in statement_formal.declarations or leg.declarations"
      return 1
    fi

    local probe_file="$work_root/__AssumptionsProbe.lean"
    {
      printf 'import %s\n' "$mod_path"
      local decl
      for decl in "${target_decls[@]}"; do
        if ! is_valid_ident "$decl"; then
          rm -f "$probe_file"
          ASSUMPTION_ERR="$full_rel ($tid): declaration '$decl' is not a valid Lean identifier — map Agda anchors to Lean identifiers in legs[].declarations"
          return 1
        fi
        printf '#print axioms %s\n' "$decl"
      done
    } >"$probe_file"

    local probe_out probe_rc
    set +e
    probe_out="$(cd "$work_root" && LEAN_PATH="$work_root:$LEAN_LIBDIR${LEAN_PATH:+:$LEAN_PATH}" lean "$probe_file" 2>&1)"
    probe_rc=$?
    set -e
    rm -f "$probe_file"

    append_receipt_section "--- [#print axioms] $full_rel ($tid :: $mod_path) ---
recorded-axioms: ${axioms_json}
declarations: $(printf '%s ' "${target_decls[@]}")
${probe_out}"

    if [[ "$probe_rc" -ne 0 ]] || grep -qE 'error:' <<<"$probe_out"; then
      ASSUMPTION_ERR="$full_rel ($tid): Lean assumption probe failed (exit $probe_rc):
$probe_out"
      return 1
    fi

    local verdict_count=0
    local seen_leg_axioms=()
    local pline pdecl pax_csv pax
    local re_clean="^([^']+:[[:space:]]*info:[[:space:]]*)?'([^']+)' does not depend on any axioms[[:space:]]*$"
    local re_ax="^([^']+:[[:space:]]*info:[[:space:]]*)?'([^']+)' depends on axioms: \\[([^]]+)\\][[:space:]]*$"

    while IFS= read -r pline; do
      [[ -z "${pline//[[:space:]]/}" ]] && continue
      if [[ "$pline" =~ $re_clean ]]; then
        verdict_count=$((verdict_count + 1))
      elif [[ "$pline" =~ $re_ax ]]; then
        pdecl="${BASH_REMATCH[2]}"
        pax_csv="${BASH_REMATCH[3]}"
        verdict_count=$((verdict_count + 1))
        local raw_list=()
        IFS=',' read -r -a raw_list <<<"$pax_csv"
        for pax in "${raw_list[@]}"; do
          pax="${pax#"${pax%%[![:space:]]*}"}"
          pax="${pax%"${pax##*[![:space:]]}"}"
          [[ -z "$pax" ]] && continue
          if [[ "$pax" == "sorryAx" ]]; then
            ASSUMPTION_ERR="$full_rel ($tid): '$pdecl' depends on 'sorryAx' — incomplete proof in $full_rel or an imported module"
            return 1
          fi
          if [[ "${#allowed_axioms[@]}" -eq 0 ]] || ! array_contains "$pax" "${allowed_axioms[@]}"; then
            ASSUMPTION_ERR="$full_rel ($tid): '$pdecl' depends on undeclared axiom '$pax' (ledger allows: [${allowed_axioms[*]:-none}])"
            return 1
          fi
          seen_leg_axioms+=("$pax")
        done
      else
        ASSUMPTION_ERR="$full_rel ($tid): unexpected output line from Lean #print axioms probe:
  $pline"
        return 1
      fi
    done <<<"$probe_out"

    if [[ "$verdict_count" -ne "${#target_decls[@]}" ]]; then
      ASSUMPTION_ERR="$full_rel ($tid): expected ${#target_decls[@]} '#print axioms' verdict(s), got $verdict_count:
$probe_out"
      return 1
    fi

    local lax
    for lax in ${allowed_axioms[@]+"${allowed_axioms[@]}"}; do
      if [[ "${#seen_leg_axioms[@]}" -eq 0 ]] || ! array_contains "$lax" "${seen_leg_axioms[@]}"; then
        ASSUMPTION_ERR="$full_rel ($tid): ledger .axioms lists '$lax', but '#print axioms' did not report '$lax' on any recorded declaration — remove stale axioms (or promote status to 'proven' if axiom-free)"
        return 1
      fi
    done
  done

  return 0
}

fails=0
unexpected_pass=0
gated_count=0
quarantine_count=0

while IFS='|' read -r root rel status note; do
  [[ -z "${root// }" ]] && continue
  case "${root#"${root%%[![:space:]]*}"}" in \#*) continue ;; esac
  printf '  %-30s %-24s ' "$root" "$rel"
  normalize_rel_path "$root" "$rel" >>"$listed_tmp"

  case "$status" in
    gated)
      gated_count=$((gated_count + 1))
      ;;
    quarantine)
      quarantine_count=$((quarantine_count + 1))
      ;;
    *)
      echo "FAIL — unknown MANIFEST status '${status}'"
      echo "        $MANIFEST_FILE accepts only 'gated' or 'quarantine'; anything else"
      echo "        would otherwise be read as quarantine and hide a broken module."
      fails=$((fails + 1))
      continue
      ;;
  esac

  if check_one "$root" "$rel"; then
    if [[ "$status" == "gated" ]]; then
      ASSUMPTION_ERR=""
      if [[ "$PROVER" == "coq" ]]; then
        work_root="$(stage_source_root "$root")"
        if ! verify_coq_assumptions "$root" "$rel" "$work_root"; then
          echo "FAIL (assumptions)"
          printf '%s\n' "${ASSUMPTION_ERR//$'\n'/$'\n        '}" | sed '1s/^/        /'
          fails=$((fails + 1))
          continue
        fi
      elif [[ "$PROVER" == "lean4" ]]; then
        work_root="$(stage_source_root "$root")"
        if ! verify_lean_assumptions "$root" "$rel" "$work_root"; then
          echo "FAIL (assumptions)"
          printf '%s\n' "${ASSUMPTION_ERR//$'\n'/$'\n        '}" | sed '1s/^/        /'
          fails=$((fails + 1))
          continue
        fi
      fi
      echo "PASS"
    else
      echo "PASS -- UNEXPECTED (quarantined module now compiles)"
      echo "        Promote '$rel' to 'gated' in $MANIFEST_FILE and update docs/status/ROADMAP.adoc."
      unexpected_pass=$((unexpected_pass + 1))
    fi
  else
    if [[ "$status" == "gated" ]]; then
      echo "FAIL"
      printf '%s\n' "${LAST_OUT//$'\n'/$'\n        '}" | sed '1s/^/        /'
      fails=$((fails + 1))
    else
      echo "fail (quarantined, expected)"
      [[ -n "${note// }" ]] && echo "        reason:$note"
    fi
  fi
done < "$MANIFEST_FILE"

# --- coverage: every proof on disk must be listed -----------------------------
echo
echo "=== manifest coverage ($PROOF_DIR) ==="
listed="$(sort -u "$listed_tmp")"
found="$(cd "$ROOT" && find "$PROOF_DIR" -name "*.$EXT" -not -path '*/build/*' 2>/dev/null | sed 's|^\./||' | sort)"
unlisted="$(comm -13 <(printf '%s\n' "$listed") <(printf '%s\n' "$found") || true)"
missing="$(comm -23 <(printf '%s\n' "$listed") <(printf '%s\n' "$found") || true)"

if [[ -n "${unlisted//[[:space:]]/}" ]]; then
  echo "FAIL: .$EXT proofs on disk but absent from $MANIFEST_FILE:"
  while IFS= read -r u; do
    [[ -n "$u" ]] && printf '  %s\n' "$u"
  done <<<"$unlisted"
  echo "      List each as 'gated' or 'quarantine'; new proofs are gated by default."
  fails=$((fails + 1))
fi
if [[ -n "${missing//[[:space:]]/}" ]]; then
  echo "FAIL: MANIFEST lists modules that do not exist (stale entries):"
  while IFS= read -r m; do
    [[ -n "$m" ]] && printf '  %s\n' "$m"
  done <<<"$missing"
  fails=$((fails + 1))
fi
if [[ -z "${unlisted//[[:space:]]/}${missing//[[:space:]]/}" ]]; then
  echo "  all $(printf '%s\n' "$found" | grep -c . || true) .$EXT file(s) accounted for"
fi

echo
if [[ "$fails" -gt 0 ]] || [[ "$unexpected_pass" -gt 0 ]]; then
  echo "RESULT: FAIL ($fails failure(s), $unexpected_pass unexpected pass(es))"
  write_receipt "FAIL" "$gated_count" "$quarantine_count" "$fails failure(s), $unexpected_pass unexpected pass(es)"
  exit 1
fi
echo "RESULT: PASS -- gated modules compile and satisfy recorded kernel assumptions; quarantined modules still fail as recorded"
write_receipt "PASS" "$gated_count" "$quarantine_count" "all gated modules compiled and passed kernel assumption checks"
