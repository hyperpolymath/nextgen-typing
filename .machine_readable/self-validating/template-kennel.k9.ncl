K9!
# SPDX-License-Identifier: MPL-2.0
# K9 Kennel-level component: nextgen-typing coordination family registry
# Security Level: Kennel (data-only, no execution)
# No signature required - safe for any use

{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "coordination-metadata",
    security = {
      leash = 'Kennel,
      trust_level = "data-only",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
    },
    metadata = {
      name = "nextgen-typing-family-registry",
      version = "1.0.0",
      description = "Declarative registry of coordinated type-research families and pipeline stages",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  config = {
    repository = "hyperpolymath/nextgen-typing",
    role = "coordination-and-cross-project-verification",
    proof_root = "verification/proofs",

    pipeline = [
      "katagoria",
      "typell",
      "typed-wasm",
      "PanLL",
    ],

    families = [
      "echo-types",
      "epistemic-types",
      "tropical-types",
      "residual-evidence-types",
      "choreographic-types",
      "secret-types",
    ],
  },

  export = {
    format = "json",
    destination = "coordination-registry.json",
  },
}
