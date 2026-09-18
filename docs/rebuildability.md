# Rebuildability

This repository is a sanitized portfolio artifact. It explains the infrastructure structure, configuration examples, operational components, and rebuild sequence; it is not a production clone. Credentials, private keys, environment identifiers, Terraform state, and runtime state are intentionally absent.

## Example deployment layout

The paths below are role-specific public examples:

| Component | Example path |
|---|---|
| VPN collector | `/usr/local/libexec/homelab-vpn-collector.py` |
| systemd service | `/etc/systemd/system/homelab-vpn-collector.service` |
| systemd timer | `/etc/systemd/system/homelab-vpn-collector.timer` |
| Agent2 include | `/etc/zabbix/zabbix_agent2.d/homelab-vpn.conf` |
| logrotate | `/etc/logrotate.d/homelab-vpn` |
| runtime state | `/var/lib/homelab-vpn/` |
| runtime log | `/var/log/homelab-vpn/` |

The collector is invoked with the read-only VICI query interface represented by the exported source; example commands must be adapted to the target host and installed dependencies.

## Rebuild sequence

1. Prepare an operating system and install the required Zabbix, strongSwan, Python/VICI, and web dependencies.
2. Recreate the network and VPN topology from the Terraform and strongSwan examples, injecting credentials externally.
3. Create runtime directories with the service account and least-privilege permissions.
4. Install the collector, systemd service/timer, Agent2 include, and logrotate configuration.
5. Restore sanitized Zabbix templates, Items, Triggers, Actions, and dashboard relationships by names and keys rather than internal IDs.
6. Validate telemetry, freshness, Problem/Recovery notification, and rollback before production use.

Public examples require environment-specific review. They cannot reproduce a production deployment without external credentials, PKI material, provider state, and platform-specific identifiers.
