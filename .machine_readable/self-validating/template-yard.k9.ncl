K9!
# SPDX-License-Identifier: MPL-2.0
# K9 Yard-level component: nextgen-typing proof-policy configuration with contracts
# Security Level: Yard (Nickel evaluation with contracts)
# Signature recommended but not required

{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "validated-config",
    security = {
      leash = 'Yard,
      trust_level = "validated-config",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
    },
    metadata = {
      name = "nextgen-typing-proof-policy-config",
      version = "1.0.0",
      description = "Contract-validated configuration for cross-project proof verification",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  config = {
    name
      | String
      | std.string.NonEmpty
      = "nextgen-typing",

    ledger_path
      | String
      | std.string.NonEmpty
      = "verification/proofs/LEDGER.json",

    strict_witnesses | Bool = true,

    source_prover
      | [| 'Agda, 'Idris2 |]
      = 'Agda,

    recheck_provers
      | Array String
      | std.array.NonEmpty
      = ["rocq", "lean4"],
  },

  validation = {
    check_recheck_provers = std.array.length config.recheck_provers >= 2,
    check_strict = config.strict_witnesses == true,
  },
}
