#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# E2E Test: Coordinator Repository Integrity
# Copies the repository into a clean temporary working tree and runs all
# structural, coordination-boundary, workflow, and proof-ledger checks.

set -euo pipefail

REPO_SOURCE="${1:-.}"
TEMP_DIR="$(mktemp -d)"
TEST_REPO_PATH="$TEMP_DIR/nextgen-typing-e2e"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cp -r "$REPO_SOURCE" "$TEST_REPO_PATH"

(
    cd "$TEST_REPO_PATH"
    bash scripts/validate-template.sh . 0
    bash scripts/check-coordination-boundary.sh
    ENROL_RC=0
    bash scripts/check-proof-enrolment.sh >/dev/null 2>&1 || ENROL_RC=$?
    if [[ "$ENROL_RC" -ne 0 ]]; then
        echo "check-proof-enrolment.sh failed with rc=$ENROL_RC" >&2
        exit 1
    fi
    bash scripts/check-proof-ledger.sh
    bash tests/workflows/validate_workflows_test.sh .github/workflows
    bash tests/aspect_tests.sh
)

echo "✓ E2E coordinator repository integrity test PASSED"
