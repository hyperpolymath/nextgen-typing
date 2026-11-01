#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Cross-project Agda proof gate (no implicit dependency download or skips).
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v agda >/dev/null 2>&1; then
  echo "FATAL: Agda is missing; proof check is not optional." >&2
  exit 1
fi
cd "$root/verification/proofs/agda"
agda --version
# The .agda-lib requires both standard-library and echo-types; echo-types
# in turn requires absolute-zero. If imports are unavailable/incompatible,
# this command fails visibly instead of fabricating a proof receipt.
agda --safe --without-K --cubical-compatible Verification.agda
