#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Proof enrolment gate.
#
# nextgen-typing hosts CROSS-project proofs (verification/proofs/) and claims
# they are machine-checked. This gate makes that claim enforceable *before*
# any prover runs, and closes the three ways a proof lane can lie:
#
#   1. UNLISTED  — a proof source on disk that nobody registered in the
#                  manifest. (Fails: silent additions cannot ride along.)
#   2. STALE     — a manifest entry with no file behind it. (Fails: the
#                  registry cannot drift away from reality.)
#   3. ZERO WORK — nothing checked at all, reported as "PASS". (Fails.)
#
# It also refuses to pretend a prover is present: a prover required by the
# manifest but missing from PATH is reported BLOCKED (exit 2), never PASS.
#
# Sources of truth (verified to agree with each other, not assumed):
#   * .machine_readable/bot_directives/placement.a2ml  [verification].allowed-proofs
#   * scripts/check-coordination-boundary.sh           ALLOWED_PROOFS
#   * the files actually present under verification/proofs/
#
# Exit codes:  0 = PASS   1 = FAIL   2 = BLOCKED (required prover missing)
#
# Usage:
#   bash scripts/check-proof-enrolment.sh [--receipt PATH]
#   bash scripts/check-proof-enrolment.sh --static-only   # skip prover probe

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

MANIFEST=".machine_readable/bot_directives/placement.a2ml"
BOUNDARY="scripts/check-coordination-boundary.sh"
PROOFS_DIR="verification/proofs"
RECEIPT=""
STATIC_ONLY=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --receipt) RECEIPT="${2:-}"; shift 2 ;;
    --receipt=*) RECEIPT="${1#--receipt=}"; shift ;;
    --static-only) STATIC_ONLY=1; shift ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

FAILS=()
BLOCKED=()
NOTES=()

fail() { FAILS+=("$1"); }

# --- prover table ------------------------------------------------------------
# extension -> label|binary|extra safety requirement
prover_label() {
  case "$1" in
    agda) echo "Agda" ;;
    idris2) echo "Idris2" ;;
    lean4) echo "Lean4" ;;
    coq) echo "Coq" ;;
    tlaplus) echo "TLA+" ;;
    *) echo "unknown" ;;
  esac
}
prover_binary() {
  case "$1" in
    agda) echo "agda" ;;
    idris2) echo "idris2" ;;
    lean4) echo "lean" ;;
    coq) echo "coqc" ;;
    tlaplus) echo "" ;;   # no prover wired for TLA+ in this repo
    *) echo "" ;;
  esac
}

# Path -> prover key, by extension. Prints nothing for non-proof-source files.
prover_of_path() {
  case "$1" in
    *.agda) echo "agda" ;;
    *.lagda) echo "agda" ;;
    *.idr) echo "idris2" ;;
    *.lean) echo "lean4" ;;
    *.v) echo "coq" ;;
    *.tla) echo "tlaplus" ;;
    *.thy) echo "isabelle" ;;   # known proof source, deliberately unwired
    *) echo "" ;;
  esac
}

echo "=== Proof enrolment gate ==="
echo "repo:     $ROOT"
echo "manifest: $MANIFEST"
echo "boundary: $BOUNDARY"
echo ""

# --- 0. required inputs exist -----------------------------------------------
[ -f "$MANIFEST" ] || { echo "FAIL: manifest not found: $MANIFEST"; exit 1; }
[ -f "$BOUNDARY" ] || { echo "FAIL: boundary guard not found: $BOUNDARY"; exit 1; }
[ -d "$PROOFS_DIR" ] || { echo "FAIL: proofs directory not found: $PROOFS_DIR"; exit 1; }

# --- 1. parse the two registries and require them to agree -------------------
# [verification].allowed-proofs = [ "path", ... ]  (comments allowed)
normalize_list_entries() {
  # strip comments, quotes, commas and all whitespace; drop blanks; sort
  sed 's/#.*//' \
    | tr -d "\"' \t\r" \
    | sed 's/,*$//' \
    | grep -v '^$' \
    | sort
}

manifest_list="$(awk '
  /^\[/ { in_section = ($0 ~ /^\[verification\]/); next }
  in_section && /^[[:space:]]*allowed-proofs[[:space:]]*=[[:space:]]*\[/ { in_list = 1; next }
  in_list && /^[[:space:]]*\][[:space:]]*$/ { in_list = 0; next }
  in_list { print }
' "$MANIFEST" | normalize_list_entries)"

boundary_list="$(awk '
  /^ALLOWED_PROOFS=\(/ { in_list = 1; next }
  in_list && /^\)/ { in_list = 0; next }
  in_list { print }
' "$BOUNDARY" | normalize_list_entries)"

if [ -z "$manifest_list" ]; then
  fail "manifest registry is empty: no allowed-proofs entries in $MANIFEST"
fi
if [ -z "$boundary_list" ]; then
  fail "boundary allowlist is empty: no ALLOWED_PROOFS entries in $BOUNDARY"
fi

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  if ! grep -Fxq -- "$entry" <<<"$boundary_list"; then
    fail "registry drift: '$entry' is in $MANIFEST but not in ALLOWED_PROOFS of $BOUNDARY"
  fi
done <<<"$manifest_list"

while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  if ! grep -Fxq -- "$entry" <<<"$manifest_list"; then
    fail "registry drift: '$entry' is in ALLOWED_PROOFS of $BOUNDARY but not in $MANIFEST"
  fi
done <<<"$boundary_list"

# --- 2. enumerate what is actually on disk ----------------------------------
disk_files="$(git ls-files -- "$PROOFS_DIR" \
  | grep -Ev '\.(a2ml|adoc|md)$|(^|/)\.gitkeep$' \
  | sort)"

disk_proofs="$(while IFS= read -r f; do
    [ -z "$f" ] && continue
    [ -n "$(prover_of_path "$f")" ] && echo "$f"
  done <<<"$disk_files")"

# --- 3. every file on disk must be registered (UNLISTED proofs fail) --------
list_size=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  list_size=$((list_size + 1))
  if ! grep -Fxq -- "$f" <<<"$manifest_list"; then
    if [ -n "$(prover_of_path "$f")" ]; then
      fail "unlisted proof source: $f
     Register it in [verification].allowed-proofs of $MANIFEST AND in
     ALLOWED_PROOFS of $BOUNDARY (see verification/proofs/README.adoc)."
    else
      fail "unregistered file under $PROOFS_DIR: $f
     Every tracked file here (including .agda-lib manifests) must be listed in
     both registries, otherwise the proof set can drift silently."
    fi
  fi
done <<<"$disk_files"

# --- 4. every registered entry must exist (STALE entries fail) --------------
while IFS= read -r entry; do
  [ -z "$entry" ] && continue
  if [ ! -e "$entry" ]; then
    fail "stale registry entry: '$entry' is registered but not present on disk"
  fi
done <<<"$manifest_list"

# --- 5. zero work is never a pass ------------------------------------------
proof_count=0
while IFS= read -r f; do
  [ -z "$f" ] && continue
  proof_count=$((proof_count + 1))
done <<<"$disk_proofs"

if [ "$proof_count" -eq 0 ]; then
  fail "zero proof sources found under $PROOFS_DIR — refusing to report PASS on zero work"
fi

# --- 6. safety flags must remain in force ----------------------------------
while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    *.agda|*.lagda)
      if ! grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--safe' "$f"; then
        fail "missing safety flag: $f does not declare --safe in its OPTIONS pragma"
      fi
      if ! grep -qE '\{-#[[:space:]]*OPTIONS[^#]*--without-K' "$f"; then
        fail "missing safety flag: $f does not declare --without-K in its OPTIONS pragma
     (If a genuinely cubical proof is being added, that is a deliberate policy
      change: update PROOF-NEEDS.adoc and this gate in the same commit.)"
      fi
      ;;
  esac
done <<<"$disk_proofs"

# --- 7. per-prover census + prover presence --------------------------------
declare -A per_prover=()
prover_order=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  key="$(prover_of_path "$f")"
  case "$key:$f" in
    agda:"$PROOFS_DIR"/agda/*.agda|idris2:"$PROOFS_DIR"/idris2/*.idr|\
    lean4:"$PROOFS_DIR"/lean4/*.lean|coq:"$PROOFS_DIR"/coq/*.v) ;;
    agda:*|idris2:*|lean4:*|coq:*)
      fail "proof source not reachable by its prover recipe: $f
     proof-check-$key only checks $PROOFS_DIR/$key/ with its canonical extension." ;;
  esac
  if [ -z "${per_prover[$key]:-}" ]; then prover_order+=("$key"); fi
  per_prover["$key"]=$(( ${per_prover["$key"]:-0} + 1 ))
done <<<"$disk_proofs"

# Stable, human-readable prover list for receipts/summaries.
prover_list=""
if [ "${#prover_order[@]}" -gt 0 ]; then
  prover_list="$(printf '%s,' "${prover_order[@]}" | sed 's/,$//')"
else
  prover_list="none"
fi

echo "--- proof sources on disk (registered: $list_size, proof sources: $proof_count) ---"
if [ "$proof_count" -gt 0 ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    printf '  %-12s %s\n' "$(prover_of_path "$f")" "$f"
  done <<<"$disk_proofs"
else
  echo "  (none)"
fi
echo ""

echo "--- required provers ---"
toolchain_report=""
if [ "${#per_prover[@]}" -eq 0 ]; then
  echo "  (none — no prover is required because no proof source is enrolled)"
else
  for key in "${prover_order[@]}"; do
    count="${per_prover[$key]}"
    bin="$(prover_binary "$key")"
    label="$(prover_label "$key")"
    if [ -z "$bin" ]; then
      fail "prover not wired: $count proof source(s) for '$key' ($label) but this repo has no prover recipe for it"
      continue
    fi
    if [ "$STATIC_ONLY" -eq 1 ]; then
      echo "  $label ($key): $count source(s); binary '$bin' not probed (--static-only)"
      toolchain_report+="  $key: not-probed"$'\n'
      continue
    fi
    if command -v "$bin" >/dev/null 2>&1; then
      ver="$("$bin" --version 2>&1 | head -n1 || true)"
      [ -z "$ver" ] && ver="(version probe produced no output)"
      echo "  $label ($key): $count source(s), $bin present — $ver"
      toolchain_report+="  $key: present ($ver)"$'\n'
      NOTES+=("$label: $ver")
    else
      echo "  $label ($key): $count source(s), $bin MISSING"
      BLOCKED+=("required prover missing: '$bin' is needed by $count $label proof source(s) but is not on PATH
     Install it, or the proof lane must stay red. A missing prover is BLOCKED,
     never a skip and never a pass.")
      toolchain_report+="  $key: MISSING"$'\n'
    fi
  done
fi
echo ""

# --- 8. receipt + verdict --------------------------------------------------
status="PASS"
[ "${#FAILS[@]}" -gt 0 ] && status="FAIL"
[ "$status" = "PASS" ] && [ "${#BLOCKED[@]}" -gt 0 ] && status="BLOCKED"

if [ -n "$RECEIPT" ]; then
  mkdir -p "$(dirname "$RECEIPT")" 2>/dev/null || true
  {
    echo "proof-enrolment receipt"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
    echo "runner: ${RUNNER_NAME:-local}/${RUNNER_OS:-$(uname -s)}"
    echo "status: $status"
    echo "registered-entries: $list_size"
    echo "proof-sources: $proof_count"
    echo "provers: $prover_list"
    echo "manifest-sha256: $(sha256sum "$MANIFEST" | cut -d' ' -f1)"
    echo "boundary-script-sha256: $(sha256sum "$BOUNDARY" | cut -d' ' -f1)"
    echo "toolchain:"
    printf '%s' "$toolchain_report"
    if [ "${#FAILS[@]}" -gt 0 ]; then
      echo "failures:"
      printf '  - %s\n' "${FAILS[@]}"
    fi
    if [ "${#BLOCKED[@]}" -gt 0 ]; then
      echo "blocked:"
      printf '  - %s\n' "${BLOCKED[@]}"
    fi
  } >"$RECEIPT"
  echo "receipt written: $RECEIPT"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Proof enrolment gate — **$status**"
      echo ""
      echo "| item | value |"
      echo "|------|-------|"
      echo "| registered entries | $list_size |"
      echo "| proof sources on disk | $proof_count |"
      echo "| provers | $prover_list |"
      echo "| receipt | \`$RECEIPT\` |"
      echo ""
    } >>"$GITHUB_STEP_SUMMARY"
  fi
fi

if [ "${#FAILS[@]}" -gt 0 ]; then
  echo "=== FAIL: ${#FAILS[@]} enrolment error(s) ==="
  printf '  ✗ %s\n' "${FAILS[@]}"
  echo ""
fi
if [ "${#BLOCKED[@]}" -gt 0 ]; then
  echo "=== BLOCKED: ${#BLOCKED[@]} required prover(s) unavailable ==="
  printf '  ⚠ %s\n' "${BLOCKED[@]}"
  echo ""
fi

case "$status" in
  PASS)
    echo "✅ PASS: $proof_count proof source(s) enrolled, registries agree, all required provers present."
    exit 0
    ;;
  FAIL)
    echo "❌ FAIL: the proof registry and/or the proof set is not in an honest state."
    exit 1
    ;;
  BLOCKED)
    echo "⚠️ BLOCKED: enrolment is consistent but a required prover is missing."
    echo "   This is NOT a pass. The proof lane stays red until the prover is installed."
    exit 2
    ;;
esac
