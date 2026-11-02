-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
/-
  =====================================================================
  EchoTyping.lean — Core Lean 4 recheck witness for XP-1 (PROOF-POLICY §2)
  =====================================================================

  Independent core Lean 4 (4.15.0, zero Mathlib, zero axioms) re-proof of
  `verification/proofs/agda/EchoTyping.agda` against the `echo-types` fiber
  constructions (`Echo`, `EchoR`, `collapse`, `Mode`, `LEcho`, `weaken`,
  `ModeLe`, `degradeMode`) and the `nextgen-typing` refinement-erasure model
  (`SurfaceTy`, `KernelTy`, `erase`).

  Universe & foundation discipline (PROOF-POLICY §2.2):
    - Primary anchors `EchoTyping.tp_echo_1`, `EchoTyping.tp_echo_2`, and
      `EchoTyping.tp_echo_3` use Type-valued `PSigma` / `PProd` (never
      Prop-truncated `Exists` / `And`) together with core Lean `Eq` (`=`),
      retaining computational witness projections (`PSigma.fst`).
    - Because Lean's `Prop` (`Eq`) has definitional proof irrelevance whereas
      Agda's `--without-K` `_≡_` is proof-relevant in `Set`, §4 below also
      checks `tp_echo_1_path`, `tp_echo_2_path`, and `tp_echo_3_path` over a
      Type-valued Martin-Löf identity type `Path` (`Sigma` + `Prod` + `Empty`),
      confirming that none of the theorems relies on UIP/K.
    - `#print axioms` reports `'does not depend on any axioms'` for every
      headline theorem (no `sorryAx`, no `propext`, no `Quot.sound`, no
      `Classical.choice`).

  Scope (matching EchoTyping.agda): proves that this pipeline's loss
  operations are instances of the `Echo` fiber construction; does not claim
  to discharge `echo-types`' own open Criterion 2 identity thesis.
-/

namespace EchoTyping

-- =====================================================================
-- § 0. Minimal Echo / EchoCharacteristic / EchoResidue / EchoLinear core
-- =====================================================================

def Echo {A B : Type} (f : A → B) (y : B) : Type :=
  PSigma (fun x : A => f x = y)

def echo_intro {A B : Type} (f : A → B) (x : A) : Echo f (f x) :=
  ⟨x, rfl⟩

def collapse : Bool → Unit := fun _ => ()

def echo_true : Echo collapse () := echo_intro collapse true
def echo_false : Echo collapse () := echo_intro collapse false

theorem echo_true_neq_echo_false : echo_true ≠ echo_false :=
  fun h => Bool.noConfusion (congrArg PSigma.fst h)

def EchoR {B C : Type} (Cert : C → B → Type) (y : B) : Type :=
  PSigma (fun r : C => Cert r y)

def echo_to_residue {A B C : Type}
    (f : A → B) (kappa : A → C) (Cert : C → B → Type)
    (sound : ∀ x : A, Cert (kappa x) (f x))
    {y : B} (e : Echo f y) : EchoR Cert y :=
  ⟨kappa e.fst, @Eq.ndrec B (f e.fst) (fun z => Cert (kappa e.fst) z) (sound e.fst) y e.snd⟩

def TrivialCert : Unit → Unit → Type := fun _ _ => Unit
def collapse_kappa : Bool → Unit := fun _ => ()
def collapse_sound (b : Bool) : TrivialCert (collapse_kappa b) (collapse b) := ()

def collapse_to_residue : Echo collapse () → EchoR TrivialCert () :=
  echo_to_residue collapse collapse_kappa TrivialCert collapse_sound

inductive Mode : Type where
  | linear : Mode
  | affine : Mode

def LEcho : Mode → Type
  | Mode.linear => Echo collapse ()
  | Mode.affine => EchoR TrivialCert ()

def weaken : LEcho Mode.linear → LEcho Mode.affine := collapse_to_residue

-- =====================================================================
-- § 1. Affine weakening (AffineScript subtyping) is structured loss.
-- =====================================================================

def affine_weakening : LEcho Mode.linear → LEcho Mode.affine := weaken

theorem affine_subtyping_forgets :
    affine_weakening echo_true = affine_weakening echo_false :=
  rfl

theorem affine_subtyping_irreversible :
    ¬ PSigma (fun (reify : LEcho Mode.affine → LEcho Mode.linear) =>
        ∀ e : LEcho Mode.linear, reify (affine_weakening e) = e) :=
  fun ⟨reify, sec⟩ =>
    echo_true_neq_echo_false
      (Eq.trans
        (Eq.symm (sec echo_true))
        (Eq.trans (congrArg reify affine_subtyping_forgets) (sec echo_false)))

theorem affine_canonical (e : LEcho Mode.affine) :
    e = PSigma.mk (β := fun r : Unit => TrivialCert r ()) () () :=
  match e with
  | ⟨(), ()⟩ => rfl

theorem affine_typing_proof_irrelevant (e₁ e₂ : LEcho Mode.affine) : e₁ = e₂ :=
  Eq.trans (affine_canonical e₁) (Eq.symm (affine_canonical e₂))

inductive ModeLe : Mode → Mode → Type where
  | linear_le_linear : ModeLe Mode.linear Mode.linear
  | linear_le_affine : ModeLe Mode.linear Mode.affine
  | affine_le_affine : ModeLe Mode.affine Mode.affine

def mode_le_trans : ∀ {m₁ m₂ m₃ : Mode}, ModeLe m₁ m₂ → ModeLe m₂ m₃ → ModeLe m₁ m₃
  | ModeLe.linear_le_linear, p23 => p23
  | ModeLe.linear_le_affine, ModeLe.affine_le_affine => ModeLe.linear_le_affine
  | ModeLe.affine_le_affine, ModeLe.affine_le_affine => ModeLe.affine_le_affine

def degradeMode : ∀ {m₁ m₂ : Mode}, ModeLe m₁ m₂ → LEcho m₁ → LEcho m₂
  | ModeLe.linear_le_linear, e => e
  | ModeLe.linear_le_affine, e => weaken e
  | ModeLe.affine_le_affine, e => e

def subsume {m₁ m₂ : Mode} (p : ModeLe m₁ m₂) : LEcho m₁ → LEcho m₂ :=
  degradeMode p

theorem subsume_coherent :
    ∀ {m₁ m₂ m₃ : Mode} (p12 : ModeLe m₁ m₂) (p23 : ModeLe m₂ m₃) (e : LEcho m₁),
      degradeMode p23 (degradeMode p12 e) = degradeMode (mode_le_trans p12 p23) e
  | ModeLe.linear_le_linear, _, _ => rfl
  | ModeLe.linear_le_affine, ModeLe.affine_le_affine, _ => rfl
  | ModeLe.affine_le_affine, ModeLe.affine_le_affine, _ => rfl

-- =====================================================================
-- § 2. Refinement erasure is a fiber (the Echo of erasure).
-- =====================================================================

inductive SurfaceTy : Type where
  | surf_nat : SurfaceTy
  | pos : SurfaceTy
  | even : SurfaceTy

inductive KernelTy : Type where
  | KernNat : KernelTy

def erase : SurfaceTy → KernelTy := fun _ => KernelTy.KernNat

def ErasedFrom (k : KernelTy) : Type := Echo erase k

def echo_from_pos : ErasedFrom KernelTy.KernNat := echo_intro erase SurfaceTy.pos
def echo_from_even : ErasedFrom KernelTy.KernNat := echo_intro erase SurfaceTy.even

theorem surface_distinct : SurfaceTy.pos ≠ SurfaceTy.even :=
  fun h => SurfaceTy.noConfusion h

def erasure_non_injective :
    PSigma (fun s₁ : SurfaceTy =>
      PSigma (fun s₂ : SurfaceTy =>
        PProd (erase s₁ = erase s₂) (s₁ ≠ s₂))) :=
  ⟨SurfaceTy.pos, ⟨SurfaceTy.even, ⟨rfl, surface_distinct⟩⟩⟩

-- =====================================================================
-- § 3. Headline pins mapped from EchoTyping.agda TP-ECHO-1..3
-- =====================================================================

theorem tp_echo_1 :
    affine_weakening echo_true = affine_weakening echo_false :=
  affine_subtyping_forgets

theorem tp_echo_2 :
    ¬ PSigma (fun (reify : LEcho Mode.affine → LEcho Mode.linear) =>
        ∀ e : LEcho Mode.linear, reify (affine_weakening e) = e) :=
  affine_subtyping_irreversible

def tp_echo_3 :
    PSigma (fun s₁ : SurfaceTy =>
      PSigma (fun s₂ : SurfaceTy =>
        PProd (erase s₁ = erase s₂) (s₁ ≠ s₂))) :=
  erasure_non_injective

-- =====================================================================
-- § 4. Proof-relevant Type-valued Martin-Löf Path companions (--without-K)
-- =====================================================================

inductive Path {α : Type} : α → α → Type where
  | refl (a : α) : Path a a

def path_sym {α : Type} {x y : α} (p : Path x y) : Path y x :=
  @Path.rec α x (fun z _ => Path z x) (Path.refl x) y p

def path_trans {α : Type} {x y z : α} (p : Path x y) (q : Path y z) : Path x z :=
  @Path.rec α x (fun w _ => Path w z → Path x z) (fun r => r) y p q

def path_cong {α β : Type} (f : α → β) {x y : α} (p : Path x y) : Path (f x) (f y) :=
  @Path.rec α x (fun z _ => Path (f x) (f z)) (Path.refl (f x)) y p

def path_subst {α : Type} (P : α → Type) {x y : α} (p : Path x y) (px : P x) : P y :=
  @Path.rec α x (fun z _ => P z) px y p

def EchoPath {A B : Type} (f : A → B) (y : B) : Type :=
  Sigma (fun x : A => Path (f x) y)

def echo_path_true : EchoPath collapse () := ⟨true, Path.refl ()⟩
def echo_path_false : EchoPath collapse () := ⟨false, Path.refl ()⟩

def bool_path_disjoint (h : Path true false) : Empty :=
  @Path.rec Bool true (fun b _ => match b with | true => Unit | false => Empty) () false h

def echo_path_distinct (h : Path echo_path_true echo_path_false) : Empty :=
  bool_path_disjoint (path_cong Sigma.fst h)

def EchoRPath {B C : Type} (Cert : C → B → Type) (y : B) : Type :=
  Sigma (fun r : C => Cert r y)

def LEchoPath : Mode → Type
  | Mode.linear => EchoPath collapse ()
  | Mode.affine => EchoRPath TrivialCert ()

def affine_weakening_path (e : LEchoPath Mode.linear) : LEchoPath Mode.affine :=
  ⟨collapse_kappa e.fst, path_subst (fun z => TrivialCert (collapse_kappa e.fst) z) e.snd (collapse_sound e.fst)⟩

def tp_echo_1_path :
    Path (affine_weakening_path echo_path_true) (affine_weakening_path echo_path_false) :=
  Path.refl ⟨(), ()⟩

def tp_echo_2_path :
    Sigma (fun (reify : LEchoPath Mode.affine → LEchoPath Mode.linear) =>
      ∀ e : LEchoPath Mode.linear, Path (reify (affine_weakening_path e)) e) → Empty :=
  fun ⟨reify, sec⟩ =>
    echo_path_distinct
      (path_trans
        (path_sym (sec echo_path_true))
        (path_trans (path_cong reify tp_echo_1_path) (sec echo_path_false)))

def surface_path_distinct (h : Path SurfaceTy.pos SurfaceTy.even) : Empty :=
  @Path.rec SurfaceTy SurfaceTy.pos
    (fun s _ => match s with | SurfaceTy.even => Empty | _ => Unit)
    () SurfaceTy.even h

def tp_echo_3_path :
    Sigma (fun s₁ : SurfaceTy =>
      Sigma (fun s₂ : SurfaceTy =>
        Prod (Path (erase s₁) (erase s₂)) (Path s₁ s₂ → Empty))) :=
  ⟨SurfaceTy.pos, ⟨SurfaceTy.even, (Path.refl KernelTy.KernNat, surface_path_distinct)⟩⟩

end EchoTyping
