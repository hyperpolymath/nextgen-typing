-- SPDX-License-Identifier: MPL-2.0
-- INSTRUMENT CONTROL — NOT an estate proof.
-- Exercises imported-axiom detection (nextgen-typing#131): contains NO banned
-- lexical token, yet `Classical.em` depends on `propext`, `Classical.choice`,
-- and `Quot.sound` from core Init. Must fail check-proofs.sh when `axioms: []`
-- and pass when `proven-with-postulates` names all three axioms.
theorem imported_em (P : Prop) : P ∨ ¬ P := Classical.em P
