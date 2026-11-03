#!/bin/bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
#
# Coordinator Gate Benchmarks
# Measures execution times of nextgen-typing validation, boundary, drift, and ledger gates.

set -euo pipefail

REPO_ROOT="${1:-.}"
OUTPUT_FORMAT="${2:-human}"  # human | json | csv

BLUE='\033[0;34m'
GREEN='\033[0;32m'
NC='\033[0m'

log_info() { echo -e "${BLUE}→${NC} $*"; }
log_pass() { echo -e "${GREEN}✓${NC} $*"; }

declare -A results

run_bench() {
    local key="$1"
    local label="$2"
    shift 2
    log_info "Benchmarking $label"
    "$@" >/dev/null 2>&1
    local runs=3
    local total=0
    for i in $(seq 1 "$runs"); do
        local start end ms
        start=$(date +%s%N)
        "$@" >/dev/null 2>&1
        end=$(date +%s%N)
        ms=$(( (end - start) / 1000000 ))
        total=$(( total + ms ))
        [ "$OUTPUT_FORMAT" = "human" ] && echo "  Run $i: ${ms}ms"
    done
    local avg=$(( total / runs ))
    results["$key"]=$avg
    log_pass "$label: ${avg}ms average (${runs} runs)"
}

echo ""
echo "═══════════════════════════════════════════════════════════════════════════════"
echo "nextgen-typing Coordinator Gate Benchmarks"
echo "═══════════════════════════════════════════════════════════════════════════════"
echo ""

run_bench "validation" "Structure validation" bash "$REPO_ROOT/scripts/validate-template.sh" "$REPO_ROOT" 0
run_bench "boundary" "Coordination boundary" bash "$REPO_ROOT/scripts/check-coordination-boundary.sh"
run_bench "ledger" "Proof ledger audit" bash "$REPO_ROOT/scripts/check-proof-ledger.sh"
run_bench "workflows" "Workflow validation" bash "$REPO_ROOT/tests/workflows/validate_workflows_test.sh" "$REPO_ROOT/.github/workflows"

case "$OUTPUT_FORMAT" in
    json)
        cat <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "benchmarks": {
    "validation_ms": ${results[validation]},
    "boundary_ms": ${results[boundary]},
    "ledger_ms": ${results[ledger]},
    "workflows_ms": ${results[workflows]}
  }
}
EOF
        ;;
    csv)
        echo "benchmark,time_ms"
        echo "validation,${results[validation]}"
        echo "boundary,${results[boundary]}"
        echo "ledger,${results[ledger]}"
        echo "workflows,${results[workflows]}"
        ;;
esac
