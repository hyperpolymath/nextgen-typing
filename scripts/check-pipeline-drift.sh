#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Pipeline drift guard for nextgen-typing.
# Ensures canonical pipeline docs and 6a2 machine-readable state stay aligned.

set -euo pipefail

REPO_ROOT="${1:-.}"
ERRORS=0

README="$REPO_ROOT/README.adoc"
ARCHITECTURE="$REPO_ROOT/docs/ARCHITECTURE.adoc"
PIPELINE="$REPO_ROOT/docs/PIPELINE.adoc"
STATE="$REPO_ROOT/.machine_readable/6a2/STATE.a2ml"
META="$REPO_ROOT/.machine_readable/6a2/META.a2ml"
ECOSYSTEM="$REPO_ROOT/.machine_readable/6a2/ECOSYSTEM.a2ml"

CANON_CHAIN="katagoria → typell → typed-wasm → PanLL"
CHAIN_REGEX='katagoria[[:space:]]*→[[:space:]]*typell[[:space:]]*→[[:space:]]*typed-wasm[[:space:]]*→[[:space:]]*PanLL'
CHAIN_REGEX_WITH_OPTIONAL_ROLES='katagoria([[:space:]]*\([^)]*\))?[[:space:]]*→[[:space:]]*typell([[:space:]]*\([^)]*\))?[[:space:]]*→[[:space:]]*typed-wasm([[:space:]]*\([^)]*\))?[[:space:]]*→[[:space:]]*PanLL([[:space:]]*\([^)]*\))?'
STALE_REGEX='Not yet created|not yet updated|Does not exist yet|🚧 Planned|has not been created yet'

# ANSI colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}INFO${NC}: $*" >&2
}

log_pass() {
    echo -e "${GREEN}PASS${NC}: $*" >&2
}

log_error() {
    echo -e "${RED}ERROR${NC}: $*" >&2
    ERRORS=$((ERRORS + 1))
}

require_file() {
    local file="$1"
    if [ -f "$file" ]; then
        log_pass "Found: ${file#$REPO_ROOT/}"
    else
        log_error "Missing required file: ${file#$REPO_ROOT/}"
    fi
}

extract_quoted_value() {
    local key="$1"
    local file="$2"
    grep -E "^[[:space:]]*$key[[:space:]]*=" "$file" | head -1 | sed -E 's/^[^"]*"([^"]+)".*/\1/' || true
}

check_contains_regex() {
    local file="$1"
    local regex="$2"
    local description="$3"
    if grep -Eq "$regex" "$file"; then
        log_pass "$description"
    else
        log_error "$description"
    fi
}

check_katagoria_active_row() {
    local file="$1"
    local row_regex="$2"
    local label="$3"
    if awk -v row_re="$row_regex" '
        $0 ~ row_re {
            getline
            if ($0 ~ /^\|[[:space:]]*.*Active/) ok=1
        }
        END { exit(ok ? 0 : 1) }
    ' "$file"; then
        log_pass "$label"
    else
        log_error "$label"
    fi
}

echo ""
log_info "Pipeline drift guard: validating canonical files and cross-file invariants"
echo ""

require_file "$README"
require_file "$ARCHITECTURE"
require_file "$PIPELINE"
require_file "$STATE"
require_file "$META"
require_file "$ECOSYSTEM"

if [ "$ERRORS" -gt 0 ]; then
    echo ""
    echo -e "${RED}Drift guard failed due to missing files.${NC}" >&2
    exit 1
fi

echo ""
log_info "Checking canonical chain and invariant language"
echo ""

check_contains_regex "$README" "$CHAIN_REGEX" "README contains canonical main chain"
check_contains_regex "$ARCHITECTURE" "$CHAIN_REGEX" "ARCHITECTURE contains canonical main chain"
check_contains_regex "$PIPELINE" "$CHAIN_REGEX" "PIPELINE contains canonical main chain"
check_contains_regex "$STATE" "$CHAIN_REGEX_WITH_OPTIONAL_ROLES" "STATE purpose contains canonical main chain"
check_contains_regex "$ECOSYSTEM" "$CHAIN_REGEX" "ECOSYSTEM purpose contains canonical main chain"

PIPE_CHAIN="$(extract_quoted_value "chain" "$PIPELINE")"
if [ "$PIPE_CHAIN" = "$CANON_CHAIN" ]; then
    log_pass "PIPELINE chain value exactly matches canonical chain"
else
    log_error "PIPELINE chain mismatch: expected '$CANON_CHAIN', got '$PIPE_CHAIN'"
fi

check_contains_regex "$README" "open-ended" "README contains open-ended TypeLL framing"
check_contains_regex "$ARCHITECTURE" "Key Invariant: TypeLL Is Open-Ended" "ARCHITECTURE contains TypeLL key invariant section"
check_contains_regex "$PIPELINE" "open-ended progressive" "PIPELINE contains open-ended progressive invariant"
check_contains_regex "$META" 'title = "TypeLL is open-ended progressive, not capped at 10 levels"' "META ADR-002 encodes open-ended TypeLL framing"

check_katagoria_active_row "$README" '^[|][[:space:]]*katagoria[[:space:]]*$' "README marks katagoria row as Active"
check_katagoria_active_row "$ARCHITECTURE" '^[|][[:space:]]*`katagoria`[[:space:]]*$' "ARCHITECTURE marks katagoria row as Active"

echo ""
log_info "Checking date synchronization across canonical state files"
echo ""

STATE_DATE="$(extract_quoted_value "last-updated" "$STATE")"
META_DATE="$(extract_quoted_value "last-updated" "$META")"
ECOSYSTEM_DATE="$(extract_quoted_value "last-updated" "$ECOSYSTEM")"
PIPELINE_VERSION="$(extract_quoted_value "version" "$PIPELINE")"
ARCH_DATE="$(grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' "$ARCHITECTURE" | head -1 || true)"

if [ -z "$STATE_DATE" ] || [ -z "$META_DATE" ] || [ -z "$ECOSYSTEM_DATE" ] || [ -z "$PIPELINE_VERSION" ] || [ -z "$ARCH_DATE" ]; then
    log_error "One or more date/version fields are missing (STATE/META/ECOSYSTEM last-updated, PIPELINE version, ARCHITECTURE header date)"
else
    if [ "$META_DATE" = "$STATE_DATE" ] && [ "$ECOSYSTEM_DATE" = "$STATE_DATE" ] && [ "$PIPELINE_VERSION" = "$STATE_DATE" ] && [ "$ARCH_DATE" = "$STATE_DATE" ]; then
        log_pass "Dates synchronized: STATE/META/ECOSYSTEM last-updated == PIPELINE version == ARCHITECTURE header date ($STATE_DATE)"
    else
        log_error "Date drift detected: STATE=$STATE_DATE META=$META_DATE ECOSYSTEM=$ECOSYSTEM_DATE PIPELINE.version=$PIPELINE_VERSION ARCHITECTURE.date=$ARCH_DATE"
    fi
fi

echo ""
log_info "Checking for known stale phrases"
echo ""

STALE_HITS="$(grep -nE "$STALE_REGEX" "$README" "$ARCHITECTURE" "$PIPELINE" "$STATE" "$META" "$ECOSYSTEM" || true)"
if [ -n "$STALE_HITS" ]; then
    log_error "Stale status phrases detected in canonical files:"
    echo "$STALE_HITS" >&2
else
    log_pass "No stale status phrases found in canonical files"
fi

if grep -Fq 'docs/PIPELINE.adoc' "$README"; then
    log_pass "README links to docs/PIPELINE.adoc"
else
    log_error "README is missing a link/reference to docs/PIPELINE.adoc"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
echo "PIPELINE DRIFT GUARD SUMMARY" >&2
echo "═══════════════════════════════════════════════════════════════════════════════" >&2
if [ "$ERRORS" -eq 0 ]; then
    echo -e "${GREEN}PASS${NC}: no pipeline drift detected." >&2
    exit 0
else
    echo -e "${RED}FAIL${NC}: $ERRORS issue(s) detected." >&2
    exit 1
fi
