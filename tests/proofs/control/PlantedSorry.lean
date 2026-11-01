-- SPDX-License-Identifier: MPL-2.0
-- INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
-- Lean compiles `sorry` and exits 0, so an exit code is NOT evidence of a
-- closed proof. The instrument relies on `#print axioms` (which shows sorryAx)
-- and on the ledger gate's escape-hatch scan. Both must reject this file.
theorem planted_true : True := sorry
#print axioms planted_true
