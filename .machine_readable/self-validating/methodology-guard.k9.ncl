K9!
# SPDX-License-Identifier: MPL-2.0
# Copyright (c) {{CURRENT_YEAR}} {{AUTHOR}} ({{OWNER}}) <{{AUTHOR_EMAIL}}>
#
# K9 Validator: Methodology Guard
# Checks that agent work respects methodology constraints declared in
# bot_directives/methodology.a2ml.
#
# Usage: k9 validate methodology-guard

let methodology_guard = {
  name = "methodology-guard",
  version = "1.0.0",
  description = "Validates that agent work respects declared methodology constraints",

  # Required by K9 validators (hyperpolymath/k9-validate-action): the magic
  # first line above and this pedigree. Data-only guard — no network/write/
  # subprocess access. (Defect found via januskey's "Validate K9 contracts"
  # gate when this template was adopted there.)
  pedigree = {
    name = "methodology-guard",
    schema_version = "1.0.0",
    component_type = "methodology-validator",
    security = {
      leash = 'Kennel,
      trust_level = "data-only",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
    },
  },

  checks = {
    divergent_invariant_language = {
      description = "No files in languages violating the divergent language invariant",
      severity = "error",
      # When methodology.divergent-invariants.language-invariant is set,
      # check that no new files introduce a different language for that purpose.
      # Example: if language-invariant = "idris2", reject new .lean or .v files
      # in the proof directories.
      check_type = "file-extension-guard",
      scope = "src/",
    },

    believe_me_ceiling = {
      description = "believe_me count must not exceed declared ceiling",
      severity = "error",
      pattern = "believe_me",
      ceiling_key = "methodology.divergent-invariants.believe-me-ceiling",
      default_ceiling = 0,
    },

    assert_total_ceiling = {
      description = "assert_total count must not exceed declared ceiling",
      severity = "error",
      pattern = "assert_total",
      ceiling_key = "methodology.divergent-invariants.assert-total-ceiling",
      default_ceiling = 0,
    },

    state_not_template = {
      description = "STATE.a2ml must not contain template placeholders",
      severity = "warning",
      file = ".machine_readable/6a2/STATE.a2ml",
      reject_patterns = ["{{PLACEHOLDER}}", "{{PROJECT}}", "rsr-template-repo"],
    },

    coverage_updated = {
      description = "coverage.a2ml should be updated within 30 days",
      severity = "info",
      file = ".machine_readable/bot_directives/coverage.a2ml",
      staleness_days = 30,
    },
  },
}
in methodology_guard
