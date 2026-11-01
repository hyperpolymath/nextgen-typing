#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Banned-pattern scan for hosted proofs.
#
# PROOF-NEEDS.adoc bans every escape hatch a prover offers:
#   believe_me, assert_total   (Idris2)
#   postulate                  (Idris2 / Agda)
#   sorry                      (Lean4)
#   Admitted                   (Coq)
#   unsafeCoerce               (Haskell)
#   Obj.magic                  (OCaml / ReScript)
#
# This scan is comment-aware: a *prose* mention (for example "zero postulates"
# in a header comment) is not an escape hatch, and flagging it trains people to
# ignore the gate. A real `postulate` declaration, `sorry`, or `Admitted` is
# still caught, because the keyword survives comment stripping.
#
# Exit codes:  0 = clean   1 = banned pattern found   2 = nothing scanned
#
# Usage: bash scripts/proof-scan-dangerous.sh [--receipt PATH]

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

PROOFS_DIR="verification/proofs"
RECEIPT=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --receipt) RECEIPT="${2:-}"; shift 2 ;;
    --receipt=*) RECEIPT="${1#--receipt=}"; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# Keyword-boundary patterns. \b keeps "postulates" (prose) out while still
# matching a bare `postulate` declaration.
PATTERNS='\b(believe_me|assert_total|postulate|sorry|Admitted|unsafeCoerce)\b|\bObj[.]magic\b'

echo "=== Scanning for dangerous patterns in proofs ==="
echo "patterns: $PATTERNS"
echo "scope:    $PROOFS_DIR"

# Strip comments (line comments: -- and //; block comments: {- -} and (* *))
# while preserving line numbers, so hits are reported against the real file.
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

FILES_SCANNED=0
HITS=0
REPORT=""

while IFS= read -r f; do
  [ -z "$f" ] && continue
  FILES_SCANNED=$((FILES_SCANNED + 1))
  matches="$(strip_comments "$f" | grep -nE -- "$PATTERNS" || true)"
  if [ -n "$matches" ]; then
    echo "  BANNED PATTERN: $f"
    echo "$matches" | sed 's/^/    line /'
    REPORT+="$f"$'\n'"$matches"$'\n'
    HITS=$((HITS + 1))
  else
    echo "  clean: $f"
  fi
done < <(find "$PROOFS_DIR" -type f \
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

echo "PASS: $FILES_SCANNED proof source(s) scanned, no banned patterns outside comments"
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
