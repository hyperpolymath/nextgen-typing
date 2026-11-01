(* SPDX-License-Identifier: MPL-2.0 *)
(* Control fixture, NOT a proof: closes a goal with Coq's admit. escape hatch.
   check-proof-ledger.sh --scan-file must refuse it. The scanner's pattern list
   names this marker, so a clean report here would mean the pattern is unfirable
   — not that the file is closed. *)

Theorem planted_admit : forall n : nat, n = n.
Proof.
  intros n.
  admit.
Qed.
