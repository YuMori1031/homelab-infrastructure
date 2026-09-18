# Known exceptions

## Zabbix Server

Unsupported 12件。IPMI、Java、SNMP trapper、VMware、Connectorなど、現在起動していない任意プロセス・機能に由来します。通常のHomeLab監視対象外であり、harmless exceptionです。

## VPN Server

`ens5` speed Item 1件。Linux仮想interfaceのため取得不能です。VPN監視やcollector監視の欠落ではありません。

## Site Bスイッチ

IF-MIB index 20000、`WBANAT-int 1()`を参照するstale/phantom LLD objectが6件あります。実在interface監視を誤除外しないため、現時点では削除・再生成抑止を行っていません。

## Catalyst設計上の例外

- CPU: 5分値telemetryのみ。公式/device-defined異常閾値なし
- Memory: C1300-8T-E-2G実機で取得方法なし
- Fan: fanless

## AP

Site A AP/Site B APはICMP Ping-onlyです。SNMPによるCPU・温度・内部状態監視は意図的に行っていません。
