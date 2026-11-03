#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# RSR Coordinator & Verification Structure Validation Script for nextgen-typing
# Verifies that the repository satisfies RSR structural, metadata, workflow,
# proof-host (OQ-001), placeholder, and SPDX requirements.

set -euo pipefail

REPO_ROOT="${1:-.}"
VERBOSE="${2:-0}"
ERRORS=0
WARNINGS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_error() { echo -e "${RED}ERROR${NC}: $*" >&2; ERRORS=$((ERRORS + 1)); }
log_warning() { echo -e "${YELLOW}WARN${NC}: $*" >&2; WARNINGS=$((WARNINGS + 1)); }
log_info() { echo -e "${BLUE}INFO${NC}: $*" >&2; }
log_pass() { echo -e "${GREEN}PASS${NC}: $*" >&2; }

check_file_exists() {
    local file="$1"
    local description="${2:-}"
    if [ -f "$REPO_ROOT/$file" ]; then
        [ "$VERBOSE" = "1" ] && log_pass "File exists: $file"
        return 0
    else
        log_error "Required file missing: $file ${description:+(${description})}"
        return 1
    fi
}

check_dir_exists() {
    local dir="$1"
    local description="${2:-}"
    if [ -d "$REPO_ROOT/$dir" ]; then
        [ "$VERBOSE" = "1" ] && log_pass "Directory exists: $dir"
        return 0
    else
        log_error "Required directory missing: $dir ${description:+(${description})}"
        return 1
    fi
}

has_spdx_header() {
    head -10 "$1" | grep -q "SPDX-License-Identifier"
}

echo ""
log_info "Phase 1: Core coordinator repository structure"
echo ""

check_file_exists "0-AI-MANIFEST.a2ml" "AI manifest (universal entry point)"
check_file_exists "README.adoc" "High-level pitch"
check_file_exists "EXPLAINME.adoc" "Developer deep-dive"
check_file_exists "LICENSE" "License file"
check_file_exists "Justfile" "Task runner"
check_file_exists "AUDIT.adoc" "Release audit gate"

check_dir_exists ".machine_readable" "Machine-readable metadata"
check_dir_exists ".github" "GitHub community metadata"
check_dir_exists "verification/proofs" "Cross-project formal proofs (OQ-001)"
check_dir_exists "docs" "Documentation"

echo ""
log_info "Phase 2: Machine-readable metadata (.machine_readable/)"
echo ""

check_file_exists ".machine_readable/descriptiles/STATE.a2ml" "Project state"
check_file_exists ".machine_readable/descriptiles/META.a2ml" "Architecture decisions"
check_file_exists ".machine_readable/descriptiles/ECOSYSTEM.a2ml" "Ecosystem position"
check_file_exists ".machine_readable/descriptiles/anchor/ANCHOR.a2ml" "Semantic boundary anchor"
check_file_exists ".machine_readable/policies/MAINTENANCE-AXES.a2ml" "Maintenance axes"

echo ""
log_info "Phase 3: GitHub Actions workflows"
echo ""

REQUIRED_WORKFLOWS=(
    "hypatia-scan.yml"
    "codeql.yml"
    "scorecard.yml"
    "quality.yml"
    "mirror.yml"
    "instant-sync.yml"
    "guix-nix-policy.yml"
    "rsr-antipattern.yml"
    "security-policy.yml"
    "wellknown-enforcement.yml"
    "workflow-linter.yml"
    "secret-scanner.yml"
    "proof-ci.yml"
    "coordination-boundary.yml"
    "dogfood-gate.yml"
    "openssf-compliance.yml"
    "governance.yml"
)

for workflow in "${REQUIRED_WORKFLOWS[@]}"; do
    if [ -f "$REPO_ROOT/.github/workflows/$workflow" ]; then
        [ "$VERBOSE" = "1" ] && log_pass "Workflow found: $workflow"
    else
        log_error "Required workflow missing: $workflow"
    fi
done

WORKFLOW_FILES=$(find "$REPO_ROOT/.github/workflows" -name "*.yml" -type f 2>/dev/null || true)
WORKFLOW_COUNT=$(echo "$WORKFLOW_FILES" | grep -c "." || true)
if [ "$WORKFLOW_COUNT" -ge 15 ]; then
    log_pass "Found $WORKFLOW_COUNT workflows (>= 15 expected)"
else
    log_warning "Found only $WORKFLOW_COUNT workflows (expected >= 15)"
fi

while IFS= read -r workflow_file; do
    [ -z "$workflow_file" ] && continue
    if ! head -5 "$workflow_file" | grep -q "SPDX-License-Identifier"; then
        log_warning "Workflow missing SPDX header: $(basename "$workflow_file")"
    fi
    if ! grep -q "^name:" "$workflow_file"; then
        log_error "Workflow missing 'name' field: $(basename "$workflow_file")"
    fi
done <<< "$WORKFLOW_FILES"

echo ""
log_info "Phase 4: Cross-project formal verification (verification/proofs/)"
echo ""

check_file_exists "verification/proofs/LEDGER.json" "Proof policy ledger"
check_file_exists "verification/proofs/agda/EchoTyping.agda" "Agda source proof (XP-1)"
check_file_exists "verification/proofs/coq/EchoTyping.v" "Rocq recheck witness (XP-1)"
check_file_exists "verification/proofs/lean4/EchoTyping.lean" "Lean 4 recheck witness (XP-1)"

echo ""
log_info "Phase 5: Placeholder token replacement"
echo ""

for file in "$REPO_ROOT/README.adoc" "$REPO_ROOT/.machine_readable/descriptiles/STATE.a2ml" "$REPO_ROOT/www/.well-known/security.txt"; do
    if [ -f "$file" ] && grep -qE '\{\{[A-Z0-9_]+\}\}' "$file" 2>/dev/null; then
        log_error "File contains unresolved placeholders: $(basename "$file")"
    fi
done
if [ -f "$REPO_ROOT/Justfile" ] && grep -q 'rsr-template-''repo' "$REPO_ROOT/Justfile" 2>/dev/null; then
    log_error "Justfile still references template default repository name"
fi
log_pass "Key files checked for unresolved placeholders"

echo ""
log_info "Phase 6: SPDX License Headers"
echo ""

SOURCE_FILES=$(find "$REPO_ROOT/verification/proofs" "$REPO_ROOT/scripts" -type f \( -name "*.agda" -o -name "*.v" -o -name "*.lean" -o -name "*.idr" -o -name "*.sh" \) 2>/dev/null || true)
SOURCE_COUNT=$(echo "$SOURCE_FILES" | grep -c "." || true)
SPDX_COUNT=0
while IFS= read -r src_file; do
    [ -z "$src_file" ] && continue
    if has_spdx_header "$src_file"; then
        SPDX_COUNT=$((SPDX_COUNT + 1))
    else
        log_warning "Source file missing SPDX header: $src_file"
    fi
done <<< "$SOURCE_FILES"

if [ "$SOURCE_COUNT" -gt 0 ]; then
    PERCENT=$((SPDX_COUNT * 100 / SOURCE_COUNT))
    log_pass "SPDX headers: $SPDX_COUNT/$SOURCE_COUNT ($PERCENT%)"
fi

echo ""
log_info "Phase 7: Documentation requirements"
echo ""

check_file_exists "docs/ARCHITECTURE.adoc" "Pipeline architecture"
check_file_exists "docs/PIPELINE.adoc" "Machine-readable pipeline spec"
check_file_exists "docs/TYPE-CONNECTIONS.adoc" "Type-family connections guide"
check_file_exists "docs/developer/ABI-FFI-README.adoc" "ABI/FFI routing note"
if [ -f "$REPO_ROOT/.github/CONTRIBUTING.md" ] || [ -f "$REPO_ROOT/CONTRIBUTING.md" ]; then
    [ "$VERBOSE" = "1" ] && log_pass "Contribution guide found"
else
    log_error "Required file missing: .github/CONTRIBUTING.md (Contribution guide)"
fi
check_file_exists "GOVERNANCE.adoc" "Governance documentation"

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "VALIDATION SUMMARY"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""
echo -e "Errors:   ${RED}${ERRORS}${NC}"
echo -e "Warnings: ${YELLOW}${WARNINGS}${NC}"
echo ""

if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}✓ Validation PASSED${NC}"
    exit 0
else
    echo -e "${RED}✗ Validation FAILED${NC}"
    exit 1
fi
