# Monitoring Design

The example monitors a Zabbix Server, VPN Server, two routers, a Catalyst switch, a NAS, and two ICMP-only access points. The custom Python collector normalizes VICI state into freshness, state, and sanitized event data consumed by Agent2 and Zabbix.

Device → Item → Trigger → Problem → Action → Slack → Recovery is the core flow. Catalyst memory and fan monitoring remain intentional exceptions when the device does not expose verified telemetry.
