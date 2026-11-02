(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
   `Admitted` closes a proof with an escape hatch. The instrument must refuse
   it: the ledger gate's escape-hatch scan fails on the token, and the kernel's
   Print Assumptions must NOT report the result as closed. *)
Theorem planted_true : True.
Proof. Admitted.
