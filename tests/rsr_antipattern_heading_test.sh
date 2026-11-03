#!/usr/bin/env bash
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
#
# Positive and negative fixture controls for `.github/workflows/rsr-antipattern.yml`
# Markdown heading detection (#121 AC 3):
#   1. Positive fixture: a real `## TypeScript Exemptions` heading enables
#      parsing of its Markdown table rows and stops at the next heading.
#   2. Negative fixture: a prose mention of `TypeScript Exemptions` followed
#      by an unrelated Markdown table must NOT match or ingest rows.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/rsr-antipattern.yml"

python3 - "$WORKFLOW" <<'PYEOF'
import pathlib, re, sys

wf_text = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")

# Extract the live heading-detection regex directly from rsr-antipattern.yml so
# any drift in the workflow is tested rather than a copy-pasted regex.
m_open = re.search(r"re\.search\(r'([^']*TypeScript \[Ee\]xemptions[^']*)',\s*line\)", wf_text)
assert m_open is not None, "Could not locate TypeScript Exemptions heading regex in rsr-antipattern.yml"
heading_pattern = re.compile(m_open.group(1))
assert m_open.group(1).startswith(r"^#{1,4}\s+"), (
    f"Heading regex is not anchored to ^#{{1,4}}\\s+: {m_open.group(1)!r}"
)

def parse_exemptions(markdown_text: str) -> list[str]:
    found = []
    in_table = False
    for line in markdown_text.splitlines():
        if heading_pattern.search(line):
            in_table = True
            continue
        if in_table and re.match(r"^#{1,4}\s+", line):
            break
        if in_table and line.startswith("|"):
            m = re.match(r"\|\s*`([^`]+)`", line)
            if m:
                found.append(m.group(1))
    return found

# 1. Positive fixture: real Markdown `## TypeScript Exemptions` heading matches,
#    and parsing stops cleanly at the next section heading.
positive_doc = """# Project Instructions

## TypeScript Exemptions

| Path | Rationale |
|------|-----------|
| `bridges/demo/*.ts` | Permitted interop bridge |

## Unrelated Table

| Path | Notes |
|------|-------|
| `forbidden/sneak.ts` | Must not be parsed |
"""
pos_rows = parse_exemptions(positive_doc)
assert pos_rows == ["bridges/demo/*.ts"], f"Positive fixture failed: got {pos_rows!r}"

# 2. Negative fixture: prose line mentioning `TypeScript Exemptions` does NOT
#    match even when followed by a backticked Markdown table.
negative_doc = """# Project Instructions

Do not add entries to the TypeScript Exemptions table without maintainer review.

| Column | Example |
|--------|---------|
| `forbidden/prose_leak.ts` | Unrelated prose table row |
"""
neg_rows = parse_exemptions(negative_doc)
assert neg_rows == [], f"Negative fixture matched prose mention: got {neg_rows!r}"

print("PASS: rsr-antipattern heading regex passed positive and negative fixtures.")
PYEOF
