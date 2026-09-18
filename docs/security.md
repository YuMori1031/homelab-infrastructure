# Security Design

Credentials, private keys, PSKs, API tokens, webhook values, runtime state, and Terraform state are external inputs. Certificate authentication, least-privilege network rules, allowlisted export, and fail-closed validation reduce accidental disclosure. Example values must not be applied directly to production.
