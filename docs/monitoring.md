# Monitoring Design

## Scope

The example covers a Zabbix 7.0 server, a VPN server, two routers, a Catalyst 1300 switch, a QNAP NAS, and two ICMP-only access points. It combines Agent2, SNMPv3, and ICMP rather than relying on a single telemetry source.

## Collection and detection

- Agent2 provides OS, service, collector freshness, Site-to-Site, and Remote Access state.
- SNMPv3 provides device telemetry, including Catalyst 1300 temperature/power/sensor state and QNAP health/storage data.
- ICMP provides availability, loss, and latency for devices where richer telemetry is intentionally out of scope.
- A Python VPN collector and three custom frontend modules present operational state and connection history.
- A nine-widget dashboard organizes health, VPN state, logs, and Problems.

The operational chain is `Item → Trigger → Problem → Action → Slack → Recovery`, including recovery notification. The public artifact documents the design without exporting runtime state or internal identifiers.

## Device-specific decisions

The Catalyst 1300 custom template covers verified CPU telemetry, temperature sensors, power state, and sensor status. Memory utilization was not exposed by the verified device interfaces, and the device is fanless; both are intentional non-monitoring decisions rather than guessed metrics. Unsupported optional features remain documented exceptions.
