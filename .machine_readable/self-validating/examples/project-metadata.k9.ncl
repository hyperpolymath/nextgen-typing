K9!
# SPDX-License-Identifier: MPL-2.0
# Kennel-level K9 component: nextgen-typing project metadata
# Security Level: Kennel (pure data, no execution)
# No signature required

{
  pedigree = {
    schema_version = "1.0.0",
    component_type = "project-metadata",
    security = {
      leash = 'Kennel,
      trust_level = "data-only",
      allow_network = false,
      allow_filesystem_write = false,
      allow_subprocess = false,
    },
    metadata = {
      name = "nextgen-typing-project-metadata",
      version = "1.0.0",
      description = "Pure data configuration for nextgen-typing coordination metadata",
      author = "Jonathan D.A. Jewell <j.d.a.jewell@open.ac.uk>",
    },
  },

  project = {
    name = "nextgen-typing",
    version = "0.1.0",
    description = "Coordination monorepo and cross-project verification host for the hyperpolymath type theory pipeline",

    repository = {
      url = "https://github.com/hyperpolymath/nextgen-typing",
      type = "git",
    },

    author = {
      name = "Jonathan D.A. Jewell",
      email = "j.d.a.jewell@open.ac.uk",
      organization = "hyperpolymath",
    },

    license = "MPL-2.0",

    keywords = [
      "type-theory",
      "formal-verification",
      "agda",
      "rocq",
      "lean4",
      "rsr",
      "hyperpolymath",
    ],
  },

  export = {
    format = "json",
    destination = "project-metadata.json",
  },
}
