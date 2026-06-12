{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
--
-- Aggregator for the nextgen-typing Agda verification layer.
-- A single `agda Verification.agda` typechecks the whole set under
-- `--safe --without-K`.  EchoTyping wires in hyperpolymath/echo-types
-- (registered as the `echo-types` Agda library; see nextgen-typing.agda-lib).
--
-- Named `Verification` rather than `All` to avoid a module-name clash
-- with echo-types' own top-level `All` (a dependency on the include path).

module Verification where

open import Properties
open import EchoTyping
