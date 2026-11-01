-- SPDX-License-Identifier: MPL-2.0
-- INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
-- Lean has no `//` comment: `{ n // n = 0 }` is subtype notation. A stripper
-- that treated `//` as a line comment would cut this line before the sorry and
-- report the file clean, so the sorry sits after the subtype on purpose.
def planted_lean_subtype : { n : Nat // n = 0 } × Nat := (⟨0, rfl⟩, sorry)
