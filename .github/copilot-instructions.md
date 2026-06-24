<!--
SPDX-License-Identifier: CC-BY-SA-4.0
Copyright (c) Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>
-->
<!-- Copyright (c) {{CURRENT_YEAR}} {{AUTHOR}} ({{OWNER}}) <{{AUTHOR_EMAIL}}> -->
<!-- Authoritative source: docs/AI-CONVENTIONS.md -->

# Copilot Instructions

## ⛔ Before Writing Anything — Placement Boundary

`nextgen-typing` is a **coordination repo**, not a code repo. Do NOT add
compiler/application code or single-project proofs here. If content implements
or proves something about ONE project, put it in that project's repo. Routing
table: `.machine_readable/bot_directives/placement.a2ml` (enforced in CI by
`scripts/check-coordination-boundary.sh`). Full guidance: `AGENTS.md`.

Only these belong here: coordination/architecture docs, `.machine_readable/`
state, estate governance/CI scaffold, and CROSS-project proofs (importing ≥2
constituent repos) under `verification/proofs/`.

## Before Writing Code

- Read `0-AI-MANIFEST.a2ml` in the repo root for canonical file locations.
- State files (.a2ml) live in `.machine_readable/` ONLY, never the root.

## License

- SPDX: `MPL-2.0` on all new files.
- Never use AGPL-3.0.
- Copyright: `{{AUTHOR}} ({{OWNER}}) <{{AUTHOR_EMAIL}}>`

## Code Style

- Use descriptive variable names.
- Annotate and document all files.
- Add SPDX header to every source file.
- Use `just` for build/test/lint commands.

## Banned Patterns

- Idris2: no `believe_me`, no `assert_total`
- Haskell: no `unsafeCoerce`, no `unsafePerformIO`
- OCaml: no `Obj.magic`
- Coq: no `Admitted`
- Lean: no `sorry`
- Rust: no `transmute` unless FFI with `// SAFETY:` comment

## Banned Languages

- No TypeScript (use ReScript)
- No Node.js / npm / bun (use Deno)
- No Go (use Rust)
- No Python (use Julia or Rust)

## Containers

- Use Podman, never Docker.
- Name the file `Containerfile`, never `Dockerfile`.
- Base image: `cgr.dev/chainguard/wolfi-base:latest`.

## State Files

Never create these in the repo root:
STATE.a2ml, META.a2ml, ECOSYSTEM.a2ml, AGENTIC.a2ml, NEUROSYM.a2ml, PLAYBOOK.a2ml.
They belong in `.machine_readable/` only.
