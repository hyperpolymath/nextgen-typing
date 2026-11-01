(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — NOT an estate proof.
   This file proves nothing about the type-theory pipeline. It exists so the
   proof CI instrument can be shown to work BOTH ways, as PROOF-POLICY §7
   requires (a gate passes conforming input and fails a planted violation):
   a closed Rocq proof must be accepted, and its Print Assumptions must say so. *)
Theorem control_true : True.
Proof. exact I. Qed.
