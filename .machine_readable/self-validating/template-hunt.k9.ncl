K9!
# SPDX-License-Identifier: MPL-2.0
# K9 Hunt-level component: nextgen-typing local verification runner
# Security Level: Hunt (full execution with Just recipes)
# ⚠️ SIGNATURE REQUIRED - Review carefully before use

{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "verification-runner",
    security = {
      leash = 'Hunt,
      trust_level = "full-system-access",
      allow_network = false,
      allow_filesystem_write = true,
      allow_subprocess = true,
      signature_required = true,
    },
    metadata = {
      name = "nextgen-typing-verification-runner",
      version = "1.0.0",
      description = "Runs coordination-boundary, pipeline-drift, and cross-project proof gates",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
    warnings = [
      "This component executes local repository verification scripts",
      "Only run from trusted sources with verified signatures",
      "Review all Just recipes before execution",
    ],
    side_effects = [
      "Writes temporary proof build artefacts and witness receipts under verification/proofs/ or /tmp",
      "Executes bash, jq, git, and installed proof kernels (Agda, Rocq, Lean 4)",
    ],
  },

  config = {
    receipt_dir
      | String
      | std.string.NonEmpty
      = "/tmp/nextgen-typing-receipts",

    dry_run | Bool = false,
  },

  recipes = {
    default = {
      recipe = "verify-coordinator",
      description = "Run coordination boundary, pipeline drift, and proof witness checks",
    },

    "verify-coordinator" = {
      dependencies = ["check-prerequisites"],
      commands = [
        "./scripts/check-coordination-boundary.sh",
        "./scripts/check-pipeline-drift.sh .",
        "./scripts/check-proof-enrolment.sh",
        "./scripts/check-proof-ledger.sh",
        "./scripts/proof-scan-dangerous.sh",
      ],
    },

    "check-prerequisites" = {
      description = "Verify required tools are available",
      commands = [
        "command -v git >/dev/null && command -v jq >/dev/null",
      ],
    },
  },

  validation = {
    check_receipt_dir = std.string.length config.receipt_dir > 0,
  },
}
