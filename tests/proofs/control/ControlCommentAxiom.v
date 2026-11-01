(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — CLEAN (must be accepted).
   A real Coq comment that mentions Axiom and admit. Nothing here is code, so
   refusing this file would be a false positive and would teach people to
   distrust the scan rather than the fixture. *)
(* Axiom mentioned_in_a_comment : False. *)
(* And a sentence containing admit, written in prose. *)
Theorem comment_control : forall n : nat, n = n.
Proof. reflexivity. Qed.
