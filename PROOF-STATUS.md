<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
# Proof Status — nextgen-typing

> Coordination repo. The only proofs tracked here are **cross-project** proofs
> (spanning ≥2 constituent repos). Single-project proof status is tracked in the
> owning repos. Requirements: `PROOF-NEEDS.md`.

## Summary

| Category | Total | Done | In Progress | Remaining |
|----------|-------|------|-------------|-----------|
| Cross-project (XP) | 1 | 1 | 0 | 0 |
| **Total** | **1** | **1** | **0** | **0** |

The earlier "0 of 7" RSR ABI/TP figure was template residue: it counted
mandatory ABI/FFI + typing proofs that belong in `typed-wasm` / `typell`, not in
this coordination layer. Those scaffold files were removed (the ABI proof
obligations are owned by `typed-wasm`).

## Proofs Present

| ID | Proof | Spans | Prover | File | Verified By |
|----|-------|-------|--------|------|-------------|
| XP-1 | Pipeline information-loss = echo-types fibers | echo-types ↔ affinescript ↔ typed-wasm | Agda (`--safe --without-K`) | `verification/proofs/agda/EchoTyping.agda` | `agda Verification.agda` |

## Verification

```bash
# Typecheck the cross-project Agda set (requires the echo-types library on the
# Agda include path; see verification/proofs/agda/nextgen-typing.agda-lib)
agda verification/proofs/agda/Verification.agda

# Enforce the coordination boundary (no project code / non-allowlisted proofs)
bash scripts/check-coordination-boundary.sh
```

## Changelog

| Date | Change | By |
|------|--------|-----|
| 2026-06-19 | Reconciled to coordination reality: removed RSR ABI/TP scaffold proofs (owned by typed-wasm/typell); tracking cross-project proofs only | maintainer |
| 2026-04-04 | Initial proof status tracking | Template |
