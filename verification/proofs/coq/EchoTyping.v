(* SPDX-License-Identifier: MPL-2.0 *)
(* Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) *)
(*
 * =====================================================================
 * EchoTyping.v — Rocq (Coq 8.18) recheck witness for XP-1 (PROOF-POLICY §2)
 * =====================================================================
 *
 * Independent Rocq re-proof of `verification/proofs/agda/EchoTyping.agda`
 * against the exact `echo-types` fiber constructions (`Echo`, `EchoR`,
 * `collapse`, `Mode`, `LEcho`, `weaken`, `ModeLe`, `degradeMode`) and the
 * `nextgen-typing` refinement-erasure model (`SurfaceTy`, `KernelTy`, `erase`).
 *
 * Universe & foundation discipline (PROOF-POLICY §2.2):
 *   - Dependent pairs use Type-valued `sigT` (`{ x : A & P x }`), never
 *     Prop-truncated `ex`, preserving proof-relevant witness projections
 *     (`projT1`).
 *   - Pairs use Type-valued `prod` (`A * B`), matching Agda `_×_`.
 *   - Equality uses Martin-Löf elimination (`eq_rect`, `eq_refl`, `eq_sym`,
 *     `eq_trans`, `f_equal`) with zero axioms (`Closed under the global
 *     context` under both `coqchk -silent -o` and `Print Assumptions`),
 *     assuming neither Streicher's K nor `JMeq_eq` nor classical choice.
 *
 * Scope (matching EchoTyping.agda): proves that this pipeline's loss
 * operations are instances of the `Echo` fiber construction; does not claim
 * to discharge `echo-types`' own open Criterion 2 identity thesis.
 *)

(* ===================================================================== *)
(* § 0. Minimal Echo / EchoCharacteristic / EchoResidue / EchoLinear core *)
(* ===================================================================== *)

(** The fibre of [f] over [y]: an input paired with evidence that it maps to [y]. *)
Definition Echo {A B : Type} (f : A -> B) (y : B) : Type :=
  { x : A & f x = y }.

Definition echo_intro {A B : Type} (f : A -> B) (x : A) : Echo f (f x) :=
  existT (fun z : A => f z = f x) x eq_refl.

Definition collapse (_ : bool) : unit := tt.

Definition echo_true : Echo collapse tt := echo_intro collapse true.
Definition echo_false : Echo collapse tt := echo_intro collapse false.

Lemma echo_true_neq_echo_false : echo_true <> echo_false.
Proof.
  intros H.
  apply (f_equal (@projT1 bool (fun b : bool => collapse b = tt))) in H.
  simpl in H.
  discriminate H.
Qed.

Definition EchoR {B C : Type} (Cert : C -> B -> Type) (y : B) : Type :=
  { r : C & Cert r y }.

(** Map an echo's input through [kappa], retaining a certificate for [y].
    [sound] supplies a certificate at each input's image under [f]. *)
Definition echo_to_residue {A B C : Type}
  (f : A -> B) (kappa : A -> C) (Cert : C -> B -> Type)
  (sound : forall x : A, Cert (kappa x) (f x))
  {y : B} (e : Echo f y) : EchoR Cert y :=
  match e with
  | existT _ x p =>
      existT (fun r : C => Cert r y) (kappa x)
        (eq_rect (f x) (fun z : B => Cert (kappa x) z) (sound x) y p)
  end.

Definition TrivialCert (_ _ : unit) : Type := unit.
Definition collapse_kappa (_ : bool) : unit := tt.
Definition collapse_sound (b : bool) : TrivialCert (collapse_kappa b) (collapse b) := tt.

Definition collapse_to_residue (e : Echo collapse tt) : EchoR TrivialCert tt :=
  echo_to_residue collapse collapse_kappa TrivialCert collapse_sound e.

Inductive Mode : Set :=
  | linear : Mode
  | affine : Mode.

Definition LEcho (m : Mode) : Type :=
  match m with
  | linear => Echo collapse tt
  | affine => EchoR TrivialCert tt
  end.

(** Forget the Boolean input of a linear echo, retaining its trivial residue. *)
Definition weaken : LEcho linear -> LEcho affine := collapse_to_residue.

(* ===================================================================== *)
(* § 1. Affine weakening (AffineScript subtyping) is structured loss.    *)
(* ===================================================================== *)

Definition affine_weakening : LEcho linear -> LEcho affine := weaken.

Theorem affine_subtyping_forgets :
  affine_weakening echo_true = affine_weakening echo_false.
Proof.
  exact eq_refl.
Qed.

Theorem affine_subtyping_irreversible :
  { reify : LEcho affine -> LEcho linear &
    forall e : LEcho linear, reify (affine_weakening e) = e } -> False.
Proof.
  intros [reify sec].
  apply echo_true_neq_echo_false.
  exact (eq_trans
           (eq_sym (sec echo_true))
           (eq_trans (f_equal reify affine_subtyping_forgets) (sec echo_false))).
Qed.

Lemma affine_canonical (e : LEcho affine) :
  e = existT (fun r : unit => TrivialCert r tt) tt tt.
Proof.
  destruct e as [r c].
  destruct r.
  destruct c.
  exact eq_refl.
Qed.

Theorem affine_typing_proof_irrelevant (e1 e2 : LEcho affine) : e1 = e2.
Proof.
  exact (eq_trans (affine_canonical e1) (eq_sym (affine_canonical e2))).
Qed.

Inductive ModeLe : Mode -> Mode -> Set :=
  | linear_le_linear : ModeLe linear linear
  | linear_le_affine : ModeLe linear affine
  | affine_le_affine : ModeLe affine affine.

Definition mode_le_trans {m1 m2 m3 : Mode}
  (p12 : ModeLe m1 m2) : ModeLe m2 m3 -> ModeLe m1 m3 :=
  match p12 in ModeLe a b return ModeLe b m3 -> ModeLe a m3 with
  | linear_le_linear => fun p23 => p23
  | linear_le_affine =>
      fun p23 =>
        match p23 in ModeLe b c
          return (match b with linear => unit | affine => ModeLe linear c end)
        with
        | linear_le_linear => tt
        | linear_le_affine => tt
        | affine_le_affine => linear_le_affine
        end
  | affine_le_affine => fun p23 => p23
  end.

(** Coerce an echo along a mode relation: equal modes leave it unchanged,
    while linear to affine applies [weaken]. *)
Definition degradeMode {m1 m2 : Mode}
  (p : ModeLe m1 m2) : LEcho m1 -> LEcho m2 :=
  match p in ModeLe a b return LEcho a -> LEcho b with
  | linear_le_linear => fun e => e
  | linear_le_affine => weaken
  | affine_le_affine => fun e => e
  end.

Definition subsume {m1 m2 : Mode}
  (p : ModeLe m1 m2) : LEcho m1 -> LEcho m2 := degradeMode p.

Theorem subsume_coherent {m1 m2 m3 : Mode}
  (p12 : ModeLe m1 m2) (p23 : ModeLe m2 m3) (e : LEcho m1) :
  degradeMode p23 (degradeMode p12 e) = degradeMode (mode_le_trans p12 p23) e.
Proof.
  destruct p12.
  - exact eq_refl.
  - refine (
      match p23 as q0 in ModeLe b c
        return (match b return ModeLe b c -> Prop with
                | linear => fun _ => True
                | affine => fun q =>
                    forall e0 : LEcho linear,
                      degradeMode q (degradeMode linear_le_affine e0) =
                      degradeMode (mode_le_trans linear_le_affine q) e0
                end) q0
      with
      | linear_le_linear => I
      | linear_le_affine => I
      | affine_le_affine => fun _ => eq_refl
      end e).
  - exact eq_refl.
Qed.

(* ===================================================================== *)
(* § 2. Refinement erasure is a fiber (the Echo of erasure).             *)
(* ===================================================================== *)

Inductive SurfaceTy : Set :=
  | surf_nat : SurfaceTy
  | pos : SurfaceTy
  | even : SurfaceTy.

Inductive KernelTy : Set :=
  | KernNat : KernelTy.

(** Erase each modelled surface type to [KernNat]. *)
Definition erase (_ : SurfaceTy) : KernelTy := KernNat.

Definition ErasedFrom (k : KernelTy) : Type := Echo erase k.

Definition echo_from_pos : ErasedFrom KernNat := echo_intro erase pos.
Definition echo_from_even : ErasedFrom KernNat := echo_intro erase even.

Lemma surface_distinct : pos <> even.
Proof.
  discriminate.
Qed.

Definition erasure_non_injective :
  { s1 : SurfaceTy &
    { s2 : SurfaceTy & ((erase s1 = erase s2) * (s1 <> s2))%type } } :=
  existT
    (fun s1 : SurfaceTy =>
      { s2 : SurfaceTy & ((erase s1 = erase s2) * (s1 <> s2))%type })
    pos
    (existT
      (fun s2 : SurfaceTy => ((erase pos = erase s2) * (pos <> s2))%type)
      even
      (pair eq_refl surface_distinct)).

(* ===================================================================== *)
(* § 3. Headline pins mapped from EchoTyping.agda TP-ECHO-1..3           *)
(* ===================================================================== *)

Theorem tp_echo_1 :
  affine_weakening echo_true = affine_weakening echo_false.
Proof.
  exact affine_subtyping_forgets.
Qed.

Theorem tp_echo_2 :
  { reify : LEcho affine -> LEcho linear &
    forall e : LEcho linear, reify (affine_weakening e) = e } -> False.
Proof.
  exact affine_subtyping_irreversible.
Qed.

Definition tp_echo_3 :
  { s1 : SurfaceTy &
    { s2 : SurfaceTy & ((erase s1 = erase s2) * (s1 <> s2))%type } } :=
  erasure_non_injective.
