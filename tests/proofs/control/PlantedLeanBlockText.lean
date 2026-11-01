-- SPDX-License-Identifier: MPL-2.0
-- INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
-- `(* ... *)` is not a comment in Lean. A scanner that stripped Coq's block
-- delimiters in every language would treat this axiom as commented out and call
-- the file clean, so this fixture keeps the per-language rule honest.
(* Axiom planted_lean_block_text : False *)
theorem planted_lean_block_text : True := trivial
