#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Coordination-boundary guard.
#
# nextgen-typing is a coordination repo: docs + machine-readable state +
# estate scaffold + CROSS-project proofs only. It must never accumulate
# compiler/application code or single-project proofs. This check fails the
# build when project code or a non-allowlisted proof appears, and points the
# author at the routing table.
#
# Routing table (authoritative): .machine_readable/bot_directives/placement.a2ml
# Human-readable:                AGENTS.md / CLAUDE.md

set -euo pipefail

ROUTE=".machine_readable/bot_directives/placement.a2ml"
fail=0
err() { printf '❌ %s\n' "$1"; fail=1; }

# --- 1. No code-project scaffolding at the repo root ------------------------
for marker in src crates Cargo.toml Cargo.lock go.mod mix.exs; do
  if [ -e "$marker" ]; then
    err "Found '$marker'. nextgen-typing is a coordination repo and must not carry a code scaffold. Route the code to its owning repo (see $ROUTE)."
  fi
done

# --- 2. Only cross-project proofs may live under verification/proofs/ -------
# Allowlist = proofs that span >=2 constituent repos. Keep it small and
# deliberate; it must match [verification].allowed-proofs in placement.a2ml.
ALLOWED_PROOFS=(
  "verification/proofs/agda/EchoTyping.agda"
  "verification/proofs/agda/Verification.agda"
  "verification/proofs/agda/nextgen-typing.agda-lib"
)
is_allowed_proof() {
  local f="$1" a
  for a in "${ALLOWED_PROOFS[@]}"; do
    [ "$f" = "$a" ] && return 0
  done
  return 1
}

if [ -d verification/proofs ]; then
  while IFS= read -r f; do
    case "$f" in
      *.a2ml | *.adoc | *.md | *.gitkeep) continue ;; # docs/metadata are fine
    esac
    if ! is_allowed_proof "$f"; then
      err "Proof outside the cross-project allowlist: $f
     Single-project proofs belong in the owning repo (kategoria / typell /
     typed-wasm / echo-types / ...). Only proofs that import or relate >=2
     constituent repos belong here. If this genuinely spans the pipeline, add
     it to ALLOWED_PROOFS here AND to [verification].allowed-proofs in $ROUTE."
    fi
  done < <(find verification/proofs -type f | sed 's|^\./||' | sort)
fi

# --- 3. No implementation/proof source languages outside verification/proofs/
# The coordination repo holds docs, .a2ml, k9/ncl, shell, and CI — not Rust,
# Zig, Idris, Agda, Lean, Coq, Isabelle, Haskell, or OCaml source.
while IFS= read -r f; do
  err "Implementation source outside the coordination boundary: $f
     Compiler / kernel / proof code belongs in the owning project repo (see $ROUTE)."
done < <(
  find . \
    -path ./.git -prune -o \
    -path ./verification/proofs -prune -o \
    -type f \( \
      -name '*.rs' -o -name '*.zig' -o -name '*.idr' -o -name '*.lean' \
      -o -name '*.v' -o -name '*.agda' -o -name '*.thy' -o -name '*.hs' \
      -o -name '*.ml' \
    \) -print | sed 's|^\./||' | sort
)

if [ "$fail" -ne 0 ]; then
  printf '\nCoordination-boundary check FAILED.\n'
  printf 'nextgen-typing coordinates the typing pipeline; it does not host project code.\n'
  printf 'See %s for where this content belongs.\n' "$ROUTE"
  exit 1
fi

printf '✅ Coordination boundary intact: docs + cross-project proofs only.\n'
