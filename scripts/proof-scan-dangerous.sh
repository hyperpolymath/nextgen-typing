#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Banned-pattern scan for hosted proofs.
#
# Two policies meet here, and this scan is deliberately the union of them:
#
#   * this repository's PROOF-NEEDS.adoc bans every escape hatch outright, and
#   * the estate docs/TRUSTED-BASE-REDUCTION-POLICY.adoc (enforced estate-wide by
#     standards scripts/check-trusted-base.sh via governance-reusable.yml) names
#     the *core tier* that must be documented at minimum:
#       Coq     Axiom | Admitted | admit.
#       Lean    axiom | sorry
#       Agda    postulate
#       Idris2  believe_me | really_believe_me | assert_total | partial
#       F*      assume val | admit_p
#       Rust/Haskell  unsafeCoerce | unsafePerformIO (soundness-relevant use)
#
# A repository may be stricter than the estate floor and may not be looser. This
# one is stricter: in proof sources, a core-tier marker fails *even when
# documented*, because the policy's disposition track exists to make escapes
# visible where a repo tolerates them, not to license them here. The disposition
# markers (TRUSTED:, AXIOM:, OWED:, JUSTIFIED:, DEBT:) and the debt register are
# checked by the estate script and by docs/proof-debt.md; this scan's job is the
# narrower, harder one.
#
# This scan is comment-aware: a *prose* mention (for example "zero postulates"
# in a header comment) is not an escape hatch, and flagging it trains people to
# ignore the gate. A real `postulate` declaration, `sorry`, or `Admitted` is
# still caught, because the keyword survives comment stripping.
#
# Exit codes:  0 = clean   1 = banned pattern found   2 = nothing scanned
#
# Usage: bash scripts/proof-scan-dangerous.sh [--receipt PATH]
#        bash scripts/proof-scan-dangerous.sh --scan-file PATH   # one file, exit 1 on a hit
#        bash scripts/proof-scan-dangerous.sh --patterns         # the pattern string
#
# `--scan-file` is the control surface: it scans the path it is given even if
# `.trusted-base-ignore` exempts it, because a fixture that must stay detectable
# cannot be tested through the tree scan. `--patterns` exists so the ledger gate
# can *use* this list instead of keeping a second copy of it.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

# Both trees: the hosted proofs, and the instrument's own fixtures. A scan
# that covers only the first would miss a real escape hatch planted in the second,
# and the estate checker scans the whole repository.
SCAN_DIRS="verification tests"
RECEIPT=""

SCAN_FILE=""
SHOW_PATTERNS=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --receipt) RECEIPT="${2:-}"; shift 2 ;;
    --receipt=*) RECEIPT="${1#--receipt=}"; shift ;;
    --scan-file) SCAN_FILE="${2:-}"; shift 2 ;;
    --scan-file=*) SCAN_FILE="${1#--scan-file=}"; shift ;;
    --patterns) SHOW_PATTERNS=1; shift ;;
    -h|--help) sed -n '2,34p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Keyword-boundary patterns. \b keeps "postulates" (prose) out while still
# matching a bare `postulate` declaration.
# Core tier of the estate policy, plus this repo's own extras (Obj.magic).
# `\b` keeps prose such as "postulates" out; the scan strips comments first, so a
# documented `AXIOM:` note is a comment and a real declaration is not.
PATTERNS='\b(believe_me|really_believe_me|assert_total|postulate|sorry|Admitted|Axiom|axiom|admit_p|admit[.]|unsafeCoerce|unsafePerformIO|%default[[:space:]]+partial|assume[[:space:]]+val)\b|\bObj[.]magic\b'

if [ "$SHOW_PATTERNS" -eq 1 ]; then
  printf '%s\n' "$PATTERNS"
  exit 0
fi

echo "=== Scanning for dangerous patterns in proofs ==="
echo "patterns: $PATTERNS"
echo "scope:    $SCAN_DIRS"

# Print $1 with line comments (-- and //) and block comments ({- -} and (* *))
# removed, preserving line numbers. Delimiters in strings are treated as comments
# and nested blocks are not supported. An awk read error returns non-zero; the
# scan's calling pipeline suppresses that error.
strip_comments() {
  awk '
    BEGIN { block = 0 }
    {
      line = $0
      out = ""
      i = 1
      n = length(line)
      while (i <= n) {
        two = substr(line, i, 2)
        if (block == 1) {
          if (two == "-}" || two == "*)") { block = 0; i += 2 } else { i += 1 }
          continue
        }
        if (two == "--" || two == "//") { break }
        if (two == "{-" || two == "(*") { block = 1; i += 2; continue }
        out = out substr(line, i, 1)
        i += 1
      }
      print out
    }
  ' "$1"
}

if [ -n "$SCAN_FILE" ]; then
  [ -f "$SCAN_FILE" ] || { echo "BLOCKED: --scan-file target does not exist: $SCAN_FILE" >&2; exit 2; }
  hits="$(strip_comments "$SCAN_FILE" | grep -nE -- "$PATTERNS" || true)
$(case "$SCAN_FILE" in
    *.idr) strip_comments "$SCAN_FILE" | grep -nE '^[[:space:]]*(partial|%default[[:space:]]+partial)\b' || true ;;
    *.fst|*.fstar) strip_comments "$SCAN_FILE" | grep -nE '^[[:space:]]*(assume|admit)\b' || true ;;
  esac)"
  hits="$(printf '%s' "$hits" | grep -v '^$' || true)"
  if [ -n "$hits" ]; then
    echo "FAIL: escape hatches in $SCAN_FILE"
    printf '%s\n' "$hits"
    exit 1
  fi
  echo "PASS: no escape hatches in $SCAN_FILE"
  exit 0
fi

FILES_SCANNED=0
HITS=0
REPORT=""
EXEMPTED=0

# Per-file scan. Split out so the exemption check and the scan cannot drift
# apart: everything that decides "is this file clean" lives here.
scan_one() {
  local f="$1" matches
  FILES_SCANNED=$((FILES_SCANNED + 1))
  # `partial` is only a core-tier marker as an Idris2 top-level modifier, and a
  # bare `assume` only in F*; both are anchored to keep identifiers and prose out.
  matches="$(strip_comments "$f" | grep -nE -- "$PATTERNS" || true)
$(case "$f" in
    *.idr) strip_comments "$f" | grep -nE '^[[:space:]]*(partial|%default[[:space:]]+partial)\b' || true ;;
    *.fst|*.fstar) strip_comments "$f" | grep -nE '^[[:space:]]*(assume|admit)\b' || true ;;
  esac)"
  matches="$(printf '%s' "$matches" | grep -v '^$' || true)"
  if [ -n "$matches" ]; then
    echo "  BANNED PATTERN: $f"
    printf '%s\n' "$matches" | sed 's/^/    line /'
    REPORT+="$f"$'\n'"$matches"$'\n'
    HITS=$((HITS + 1))
  else
    echo "  clean: $f"
  fi
}

IGNORE_FILE=".trusted-base-ignore"
IGNORE_PATTERNS=()
if [ -f "$IGNORE_FILE" ]; then
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    IGNORE_PATTERNS+=("$line")
  done < <(sed 's/[[:space:]]*$//' "$IGNORE_FILE")
fi

is_ignored() {
  local f="$1" p
  for p in "${IGNORE_PATTERNS[@]:-}"; do
    [ -z "$p" ] && continue
    case "$f" in *"$p"*) return 0 ;; esac
  done
  return 1
}

EXEMPTED=0

while IFS= read -r f; do
  [ -z "$f" ] && continue
  # A path exempted in .trusted-base-ignore is not scanned. The file exists for
  # fixtures that must stay detectable and for whole-path exemptions with a
  # written rationale; the estate checker reads the same file, so the two gates
  # cannot disagree about what is exempt.
  if is_ignored "$f"; then EXEMPTED=$((EXEMPTED + 1)); continue; fi
  scan_one "$f"
done < <(find $SCAN_DIRS -type f \
           \( -name '*.agda' -o -name '*.lagda' -o -name '*.idr' \
              -o -name '*.lean' -o -name '*.v' -o -name '*.tla' \) \
           | sed 's|^\./||' | sort)

echo ""
if [ "$FILES_SCANNED" -eq 0 ]; then
  echo "FAIL: no proof sources scanned — refusing to report a clean scan on zero work"
  [ -n "$RECEIPT" ] && printf 'status: FAIL\nreason: zero files scanned\n' >"$RECEIPT"
  exit 1
fi

if [ "$HITS" -gt 0 ]; then
  echo "FAIL: $HITS file(s) contain banned proof escape hatches"
  if [ -n "$RECEIPT" ]; then
    {
      echo "proof-scan receipt"
      echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
      echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
      echo "status: FAIL"
      echo "files-scanned: $FILES_SCANNED"
      echo "files-with-hits: $HITS"
      printf '%s' "$REPORT"
    } >"$RECEIPT"
  fi
  exit 1
fi

# Estate policy docs/TRUSTED-BASE-REDUCTION-POLICY.adoc: a proof-bearing
# repository maintains a proof-debt register, and every escape hatch is one of
# discharged / budgeted / necessary-axiom / debt. This repo tolerates none, so
# the register is expected to be empty — but it must exist, because "no file"
# and "not examined" look identical from outside. The estate checker enforces the
# same rule with the same file, so the two gates agree.
DEBT_DOC=""
for c in docs/proof-debt.md docs/proof-debt.adoc PROOF-NEEDS.md PROOF-NEEDS.adoc; do
  [ -f "$c" ] && { DEBT_DOC="$c"; break; }
done
if [ -z "$DEBT_DOC" ]; then
  echo "FAIL: no proof-debt register (docs/proof-debt.md) — TRUSTED-BASE-REDUCTION-POLICY requires one in a proof-bearing repo"
  [ -n "$RECEIPT" ] && printf 'status: FAIL\nreason: no proof-debt register\n' >"$RECEIPT"
  exit 1
fi

echo "PASS: $FILES_SCANNED proof source(s) scanned, no banned patterns outside comments"
echo "      exempted by .trusted-base-ignore: $EXEMPTED;  proof-debt register: $DEBT_DOC"
if [ -n "$RECEIPT" ]; then
  {
    echo "proof-scan receipt"
    echo "generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "commit: ${GITHUB_SHA:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}"
    echo "status: PASS"
    echo "files-scanned: $FILES_SCANNED"
    echo "files-with-hits: 0"
  } >"$RECEIPT"
fi
exit 0
