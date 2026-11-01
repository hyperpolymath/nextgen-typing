(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — NOT an estate proof.
   Exercises imported-axiom detection (nextgen-typing#131): contains NO banned
   lexical token, yet depends on `Coq.Logic.Classical_Prop.classic` across a
   module import. Must fail check-proofs.sh when `axioms: []` and pass when
   `proven-with-postulates` names `Coq.Logic.Classical_Prop.classic`. *)
From Coq Require Import Logic.Classical_Prop.
Theorem imported_em : forall P : Prop, P \/ ~ P.
Proof. exact classic. Qed.
