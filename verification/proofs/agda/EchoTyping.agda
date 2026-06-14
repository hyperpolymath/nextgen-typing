{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
--
-- =====================================================================
-- EchoTyping — echo-types integrated into the type-theory pipeline
-- =====================================================================
--
-- This module wires the hyperpolymath/echo-types library (the canonical,
-- mechanised formalisation of *fiber-based structured loss*) into the
-- nextgen-typing verification layer.  The thesis is concrete:
--
--   The pipeline's information-LOSING typing operations — affine
--   weakening (AffineScript: linear ⊑ affine) and refinement erasure
--   (surface type ⇒ kernel type) — are not ad-hoc.  Each is an instance
--   of echo-types' `Echo f y := Σ A (λ x → f x ≡ y)`, the proof-relevant
--   record of *which* inputs a non-injective map collapses together.
--
-- By depending on echo-types here, the type system and its formalisation
-- share ONE mechanised notion of structured loss rather than two drifting
-- definitions.  Every theorem below is machine-checked under
-- `--safe --without-K`, zero postulates, against the real echo-types
-- source (registered in ~/.agda/libraries as `echo-types`).
--
-- See:
--   * echo-types `EchoLinear.agda`   (linear/affine modes; `weaken`)
--   * echo-types `EchoResidue.agda`  (`no-section-collapse-to-residue`)
--   * echo-types `Echo.agda`         (the fiber type itself)
--   * nextgen-typing main chain: katagoria → typell → typed-wasm → PanLL
--     (AffineScript & Ephapax cross-language calls go via typed-wasm).

module EchoTyping where

open import Echo using (Echo; echo-intro)
open import EchoCharacteristic using (echo-true; echo-false; echo-true≢echo-false)
open import EchoLinear
  using ( Mode; linear; affine; LEcho; weaken
        ; weaken-collapses-distinction; no-section-weaken
        ; affine-canonical; affine-all-equal
        ; _≤m_; linear≤linear; linear≤affine; affine≤affine
        ; degradeMode; degradeMode-comp )

open import Data.Product.Base using (Σ; _,_; _×_; proj₁; proj₂)
open import Data.Empty using (⊥)
open import Relation.Nullary using (¬_)
open import Relation.Binary.PropositionalEquality using (_≡_; _≢_; refl)


-- =====================================================================
-- § 1. Affine weakening (AffineScript subtyping) is structured loss.
-- =====================================================================
--
-- AffineScript types are affine: a `linear` value (used exactly once)
-- may be subsumed to an `affine` value (used at most once).  That
-- subsumption FORGETS the linearity obligation.  echo-types models the
-- two modes as `LEcho linear` / `LEcho affine` and the subsumption as
-- `weaken`.  We re-export the load-bearing facts under typing names so a
-- silent upstream change to echo-types trips this module.

-- The subtyping coercion linear ⊑ affine.
affine-weakening : LEcho linear → LEcho affine
affine-weakening = weaken

-- Two distinct linear typings become indistinguishable once weakened:
-- the type system cannot tell them apart at affine mode.
affine-subtyping-forgets :
  affine-weakening echo-true ≡ affine-weakening echo-false
affine-subtyping-forgets = weaken-collapses-distinction

-- No type checker can recover the linear typing from an affine one:
-- the weakening coercion has NO section.  This is the formal statement
-- that affine subtyping is irreversibly information-losing.
affine-subtyping-irreversible :
  ¬ (Σ (LEcho affine → LEcho linear)
       (λ reify → ∀ e → reify (affine-weakening e) ≡ e))
affine-subtyping-irreversible = no-section-weaken

-- At affine mode every witness is equal: the linearity evidence is gone
-- (affine typing is proof-irrelevant in its residue).
affine-typing-proof-irrelevant : ∀ (e₁ e₂ : LEcho affine) → e₁ ≡ e₂
affine-typing-proof-irrelevant = affine-all-equal

-- The subsumption order on modes, and its echo-types degradation action.
subsume : ∀ {m₁ m₂ : Mode} → m₁ ≤m m₂ → LEcho m₁ → LEcho m₂
subsume = degradeMode

-- Subtyping is coherent: coercing in two steps agrees with the direct
-- coercion (degradation composes).  Type inferred from echo-types so the
-- pipeline inherits coherence rather than re-proving it.
subsume-coherent = degradeMode-comp


-- =====================================================================
-- § 2. Refinement erasure is a fiber (the Echo of erasure).
-- =====================================================================
--
-- A surface type system carries refinements (`pos`, `even`) that the
-- typed-wasm / kernel layer erases to a single base type.  Erasure is
-- the lossy classifier; its Echo at the kernel type records WHICH
-- surface refinement was discarded.  This is a self-contained worked
-- example: it builds the fiber, not merely re-exports it.

data SurfaceTy : Set where
  nat  : SurfaceTy   -- the base type
  pos  : SurfaceTy   -- refinement: a positive nat
  even : SurfaceTy   -- refinement: an even nat

data KernelTy : Set where
  Nat : KernelTy

-- The kernel forgets all refinements: a non-injective erasure.
erase : SurfaceTy → KernelTy
erase _ = Nat

-- The structured loss of erasure at `Nat`: which surface type erased here.
ErasedFrom : KernelTy → Set
ErasedFrom k = Echo erase k

-- `pos` and `even` are distinct surface typings whose Echoes both live
-- over the SAME kernel type — the refinement is lost in the codomain but
-- retained in the fiber.
echo-from-pos : ErasedFrom Nat
echo-from-pos = echo-intro erase pos

echo-from-even : ErasedFrom Nat
echo-from-even = echo-intro erase even

-- Distinct surface refinements really are distinct (the loss is real).
surface-distinct : pos ≢ even
surface-distinct ()

-- Erasure is non-injective, witnessed concretely: two surface types that
-- erase to one kernel type yet are not equal.  `Echo erase Nat` is the
-- object the kernel would need to invert erasure — and cannot, in
-- general, by the same no-section argument as affine weakening.
erasure-non-injective :
  Σ SurfaceTy (λ s₁ → Σ SurfaceTy (λ s₂ →
    (erase s₁ ≡ erase s₂) × (s₁ ≢ s₂)))
erasure-non-injective = pos , even , refl , surface-distinct


-- =====================================================================
-- § 3. Headline pins (these names are the public typing API of Echo).
-- =====================================================================
--
-- TP-ECHO-1 : affine subtyping forgets a distinction      (§1)
-- TP-ECHO-2 : affine subtyping is irreversible (no section)(§1)
-- TP-ECHO-3 : refinement erasure is non-injective          (§2)
--
-- A green typecheck of this module is the proof that the pipeline's
-- structured-loss typing operations are exactly echo-types echoes.

TP-ECHO-1 : affine-weakening echo-true ≡ affine-weakening echo-false
TP-ECHO-1 = affine-subtyping-forgets

TP-ECHO-2 :
  ¬ (Σ (LEcho affine → LEcho linear)
       (λ reify → ∀ e → reify (affine-weakening e) ≡ e))
TP-ECHO-2 = affine-subtyping-irreversible

TP-ECHO-3 :
  Σ SurfaceTy (λ s₁ → Σ SurfaceTy (λ s₂ →
    (erase s₁ ≡ erase s₂) × (s₁ ≢ s₂)))
TP-ECHO-3 = erasure-non-injective
