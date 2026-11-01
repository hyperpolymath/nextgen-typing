-- SPDX-License-Identifier: MPL-2.0
-- INSTRUMENT CONTROL — NOT an estate proof.
-- Shows the Lean half of the instrument: `#print axioms` reports that a closed
-- proof depends on nothing (mathesis §6 axiom tracking). Must be accepted.
theorem control_true : True := True.intro
#print axioms control_true
