<!--
SPDX-License-Identifier: MPL-2.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Proof Requirements — nextgen-typing

> **nextgen-typing is a coordination repo.** It does not own compiler or
> application code, so it has **no single-project proof obligations**. The
> RSR-template "mandatory ABI/FFI + typing proofs" do **not** apply here —
> those obligations live in the repos that own the code (e.g. ABI/FFI and
> memory-layout proofs belong in `typed-wasm`; kernel proofs in `typell`).
>
> This repo hosts only **cross-project** proofs — proofs that import or relate
> two or more constituent repos. Routing: `.machine_readable/bot_directives/placement.a2ml`.

## Proof Tier

**Tier**: T5 — Exempt (coordination layer; no owned code to prove).
Cross-project proofs are hosted, not mandated.

## Cross-Project Proofs (the only category that applies here)

| # | Proof | Spans | Prover | Status | File |
|---|-------|-------|--------|--------|------|
| XP-1 | Pipeline information-loss = echo-types fibers (affine weakening + refinement erasure) | echo-types ↔ affinescript ↔ typed-wasm | Agda | Present | `verification/proofs/agda/EchoTyping.agda` |

A proof qualifies for this list only if it relates ≥2 constituent repos. When
adding one, register it in `[verification].allowed-proofs` of
`placement.a2ml` and in `ALLOWED_PROOFS` of
`scripts/check-coordination-boundary.sh`.

## Where single-project proofs go (NOT here)

| Subject | Owning repo |
|---------|-------------|
| ABI/FFI, memory layout, pointer safety, C-ABI compliance, WasmGC safety | `typed-wasm` |
| TypeLL kernel: dependent/linear/session types, QTT, proof-carrying code | `typell` |
| echo-types library internals (Echo/EchoLinear/EchoResidue) | `echo-types` |
| Research prototypes / PoCs | `kategoria` |
| Tropical / semiring type theory | `tropical-resource-typing` |

## Dangerous Patterns (BANNED in any hosted proof)

| Pattern | Language | Meaning |
|---------|----------|---------|
| `believe_me` | Idris2 | Unsafe cast / trust-me |
| `assert_total` | Idris2 | Skip totality check |
| `postulate` | Idris2/Agda | Unproven axiom |
| `sorry` | Lean4 | Incomplete proof |
| `Admitted` | Coq | Incomplete proof |
| `unsafeCoerce` | Haskell | Unsafe type cast |
| `Obj.magic` | OCaml/ReScript | Unsafe type cast |

CI rejects any PR introducing these (`panic-attack assail`).

## References

- Routing table: `.machine_readable/bot_directives/placement.a2ml`
- CI guard: `scripts/check-coordination-boundary.sh` / `.github/workflows/coordination-boundary.yml`
- Proof status tracking: `PROOF-STATUS.md` (this repo)
