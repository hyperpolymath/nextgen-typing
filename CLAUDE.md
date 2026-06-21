<!-- SPDX-License-Identifier: MPL-2.0 -->
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
| Tropical / semiring type theory (Isabelle/Lean) | `tropical-resource-typing` |
| Transport-adapter / max-plus pathfinding | `protocol-squisher` |
| Any compiler/app code, single-project ABI/FFI, benchmarks, or tests | the owning project repo |

**Rule of thumb:** if it *implements* or *proves* something about **one**
project, it does **not** go here. If you are unsure where something belongs,
open an issue in this repo proposing a home — do **not** commit code here on spec.

The machine-readable form of this table is the source of truth:
`.machine_readable/bot_directives/placement.a2ml`. It is enforced in CI by
`.github/workflows/coordination-boundary.yml`.

## After the boundary, follow the estate conventions

1. Read `0-AI-MANIFEST.a2ml`, then `.machine_readable/6a2/STATE.a2ml`.
2. Full rules: `docs/practice/AI-CONVENTIONS.adoc`.
3. Licence **MPL-2.0** + SPDX header on every file (never AGPL).
4. Banned languages: TypeScript→ReScript, npm/Node→Deno, Go→Rust, Python→Julia/Rust.
   Containers: Podman + `Containerfile`. Build/test via `just`.
5. No unsound escape hatches in any proof: `believe_me`, `assert_total`,
   `postulate`, `sorry`, `Admitted`, `unsafeCoerce`, `Obj.magic`.
6. Author: Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>.
