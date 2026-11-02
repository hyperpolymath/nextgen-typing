(* SPDX-License-Identifier: MPL-2.0 *)
(* INSTRUMENT CONTROL — PLANTED VIOLATION (must be rejected).
   `Axiom` is a Coq escape hatch in the estate policy's CORE tier
   (docs/TRUSTED-BASE-REDUCTION-POLICY.adoc) — a proposition asserted rather
   than proved. It is in this file, not in a proof, so that the scanner can be
   shown to catch it; the file is exempted by path in .trusted-base-ignore for
   that reason. *)
Axiom planted_axiom : False.
