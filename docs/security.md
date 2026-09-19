# Security Design

The publication boundary is explicit and one-way:

`Private Source of Truth → explicit allowlist → structured sanitization → generated artifact → independent validation → Public Repository`

The exporter rejects unknown files, unsafe paths, symlinks, binary sources, malformed mappings, and invalid destinations. The validator independently checks secrets, environment identifiers, file structure, links, JSON, Python syntax, and the Mermaid block.

Certificate-based authentication, PKI/CRL lifecycle controls, least-privilege permissions, and external credential injection are part of the infrastructure design. Passwords, private keys, PSKs, API tokens, webhooks, SNMP credentials, Terraform state, runtime state, and runtime logs are excluded from the public artifact.

Example configuration is for design communication only and must be reviewed before any deployment.
