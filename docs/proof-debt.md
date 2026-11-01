<!-- SPDX-License-Identifier: MPL-2.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# Proof debt

Dispositions per `docs/TRUSTED-BASE-REDUCTION-POLICY.adoc` (estate policy,
enforced by `scripts/check-trusted-base.sh` through `governance-reusable.yml`).
Scope: this repository is proof-bearing — `verification/proofs/agda/` carries
XP-1 (see `verification/proofs/LEDGER.json` and `PROOF-STATUS.adoc`).

The file exists even though the answer is "nothing outstanding", because an
absent file is indistinguishable from an unexamined repository, and the policy
requires a proof-bearing repo to maintain one.

## (a) Discharged in this repo

- (none — no escape hatch has ever been present in this repository's proof
  sources to discharge)

`Verification.agda` and `EchoTyping.agda` declare `{-# OPTIONS --safe
--without-K #-}` and the instrument invokes them with
`agda --safe --without-K --cubical-compatible`. Under `--safe` the compiler
refuses `postulate` and the unsafe pragmas, so the absence above is enforced by
the toolchain rather than asserted here. `scripts/proof-scan-dangerous.sh` scans
the same files, comment-aware, on every run; the ledger's `import_cone` records
each imported module's postulate count (0 at the pin).

## (b) Budgeted — tested with refutation budget

- (none — nothing in this repository needs a refutation budget, because there is
  nothing to refute: no `unsafe` extraction boundary, no FFI, no partially-total
  definition in a proof source)

## (c) Necessary axiom

- (none) Nothing in this repository rests on an axiom. The one theorem is
  `proven` with zero postulates, so there is no axiom to justify or cite. The
  external developments it consumes are recorded in the ledger instead — see
  `verification/proofs/LEDGER.json` `.source.assumptions` and `.source.caveats`
  — because a dependency's own obligations are that dependency's to discharge,
  not an axiom of this proof.

## (d) DEBT — actively to be closed

- (none)

## Exemptions, and why they are not debt

`.trusted-base-ignore` exempts the whole of `tests/proofs/control/`, which holds
the both-ways controls for the proof gate. Four planted files
(`PlantedAdmitted.v`, `PlantedSorry.lean`, `PlantedAxiom.v`, `PlantedAdmit.v`)
contain a real `Admitted`, a real `sorry`, a real `Axiom` and a real Coq
`admit.` **so that they are detected**: `tests/proofs/run-ledger-controls.sh`
fails if the instrument accepts any of them, and control 35 exists specifically
because the `admit.` alternative had become unfirable. The remaining fixtures
(`Control.v`, `Control.lean`) are closed proofs and contain no escape hatch;
they are exempted only because the exemption is by directory. Recording any of
these here as debt would both misreport the repository and invite someone to
"fix" the fixtures.

## How this file is kept honest

- The estate checker runs on every push via `governance-reusable.yml`
  (`trusted-base` job) and fails on a naked core marker.
- `scripts/proof-scan-dangerous.sh` fails on any core-tier marker outside the
  exempted path, and fails if this file is missing while one exists.
- Neither gate is "declared": both can fail on a planted violation, which is
  what `tests/proofs/run-ledger-controls.sh` asserts.
