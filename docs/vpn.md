# VPN Design

The sanitized example models Site-to-Site VPN links between a current cloud segment, Site A, and Site B, plus a Remote Access VPN for roaming clients. It uses strongSwan concepts rather than production credentials or endpoints.

## Authentication and PKI

- EAP-TLS authenticates Remote Access clients with client certificates.
- Server and site certificates identify VPN peers.
- A CA issues certificates and a CRL records revocations.
- Issue, revoke, and CRL generation are explicit lifecycle operations.

## Addressing and selectors

The example uses `10.10.0.0/24` for the current cloud segment, `10.10.1.0/24` for Site A, `10.10.2.0/24` for Site B, and `10.10.255.0/24` for the Remote Access pool. The Remote Access local traffic selector is represented as `10.10.0.0/16`; exact selectors are deployment inputs.

## Operations

The VPN collector reads read-only VICI state, normalizes connection and event information, and exposes freshness/state data through Agent2 to Zabbix. Zabbix evaluates this data alongside network availability and sends Problem and Recovery notifications through its Action layer.

Private keys, credentials, runtime state, and production FQDNs are intentionally excluded.
