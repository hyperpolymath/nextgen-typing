(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
   Coq's `admit.` closes a goal without proving it. It is named in the scanner's
   pattern list, and this file exists to show that the pattern can actually reach
   it: a trailing \\b after the full stop made the alternative unfirable, so the
   scan called this file clean. Not a proof; a control. *)
Theorem planted_admit : forall n : nat, n = n.
Proof.
  intros n.
  admit.
Qed.
