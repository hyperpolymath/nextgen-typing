<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->
<!-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk> -->

# CLAUDE.md — read this before writing any file

> This file is **identical to `AGENTS.md`** and exists so tools that look for
> `CLAUDE.md` get the same rules. The machine-readable routing table is
> `.machine_readable/bot_directives/placement.a2ml` (authoritative).

## ⛔ STOP — `nextgen-typing` is a COORDINATION repo, not a code repo

It **documents and connects** the hyperpolymath type-theory pipeline. It does
**NOT** contain compiler, kernel, language, or single-project code — and that
includes proofs, benchmarks, and tests that belong to one project.

**If you are about to add implementation code or a single-project proof here:
stop and put it in the owning repo instead** (table below). Adding project code
to this repo is the single most common mistake agents make here, and CI will
reject it (`scripts/check-coordination-boundary.sh`).

The pipeline:

```
katagoria → typell → typed-wasm → PanLL      (TypeFix Zero / μType₀ sits beside it)
(research)  (kernel)  (target)    (eNSAID env)
```

## ✅ What belongs HERE — and only this

- Coordination & architecture docs: `README.adoc`, `ROADMAP.adoc`, `TOPOLOGY.md`,
  `docs/ARCHITECTURE.adoc`, `docs/PIPELINE.adoc`, ADRs in `docs/decisions/`.
- Machine-readable pipeline state: `.machine_readable/`.
- Estate governance / CI scaffold shared across hyperpolymath repos.
- **Cross-project** formal proofs in `verification/proofs/` — *only* proofs that
  import/relate **two or more** constituent repos. The one current example is
  `verification/proofs/agda/EchoTyping.agda`, which relates the `echo-types`
  library to the AffineScript/typed-wasm pipeline.
- Research artefacts that genuinely span multiple projects.

## ❌ What does NOT belong here — route it to the owning repo

| If the content is about… | Put it in… |
|---|---|
| Type-theory research prototypes, Idris2/Lean PoCs, reading notes | `kategoria` |
| The TypeLL kernel: dependent / linear / session types, QTT, proof-carrying code, effects | `typell` |
| WasmGC memory-safety proofs, the verified convergence ABI, aggregate-library conventions | `typed-wasm` |
| The echo-types library itself (Echo / EchoLinear / EchoResidue / structured-loss) | `echo-types` (Agda) · `EchoTypes.jl` (Julia) |
| Choreographic / multiparty session types | `choreographic-types` |
| TypeFix Zero / μType₀ calibration calculus | `typefix-zero` |
| AffineScript / Ephapax language code | `affinescript` · `ephapax` |
| Query-language type safety (SQL/GraphQL/Cypher/SPARQL/VQL) | `typedqliser` · `vcl-ut` |
| Tropical / semiring type theory (Isabelle/Lean) | `tropical-types` (renamed from `tropical-resource-typing`, 2026-09-09) |
| Transport-adapter / max-plus pathfinding | `protocol-squisher` |
| Any compiler/app code, single-project ABI/FFI, benchmarks, or tests | the owning project repo |

**Rule of thumb:** if it *implements* or *proves* something about **one**
project, it does **not** go here. If you are unsure where something belongs,
open an issue in this repo proposing a home — do **not** commit code here on spec.

The machine-readable form of this table is the source of truth:
`.machine_readable/bot_directives/placement.a2ml`. It is enforced in CI by
`.github/workflows/coordination-boundary.yml`.

## Proofs and verification

The normative policy is *outside* this repository:
`3-practice/PROOF-POLICY.adoc` in `metadatastician/standards`, owner ruling
2026-10-26, amended 2026-11-01, pinned at commit
`46ee18323305d5b36e2eef936e47dd54c39ea736`. It is referenced, not vendored — a
bare path is a dangling citation, so name the commit or the URL.

It decides *where* a proof lives: theory → **Agda**, rechecked in **Rocq and
Lean** (§2, with the canonical invocation in §2.1); engineering/ABI → **Idris2**;
Rust → Creusot, Ada → SPARK. A gate that enforces it must be verified **both
ways** (§7): it passes conforming input *and* fails a planted violation.

Status lives in `verification/proofs/LEDGER.json`, never in prose:

```bash
just proof-witness-check        # CI target: registry gates + ledger audit + declared recheck legs
just proof-grade                # the grade ladder and the delta to the next rung
bash tests/proofs/run-controls.sh   # the §7 controls (ledger-form + kernel)
```

A missing prover is **BLOCKED**, never a skip. `docs/decisions/` records the
local rulings where they differ from the policy, including what was superseded.

## After the boundary, follow the estate conventions

1. Read `0-AI-MANIFEST.a2ml`, then `.machine_readable/descriptiles/STATE.a2ml`.
2. Full rules: `docs/practice/AI-CONVENTIONS.adoc`.
3. Licence **MPL-2.0** + SPDX header on every file (never AGPL).
4. Banned languages: TypeScript→ReScript, npm/Node→Deno, Go→Rust, Python→Julia/Rust.
   Containers: Podman + `Containerfile`. Build/test via `just`.
5. No unsound escape hatches in any proof: `believe_me`, `assert_total`,
   `postulate`, `sorry`, `Admitted`, `unsafeCoerce`, `Obj.magic`.
6. Author: Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>.
