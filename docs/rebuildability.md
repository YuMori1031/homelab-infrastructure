# HomeLab monitoring rebuild runbook

この手順は破壊的操作を自動実行するものではない。各工程で対象、差分、権限を確認し、想定外の差異・secret露出・既存サービス影響があれば STOP する。内部 ID は現環境固有であり、再構築時は名前・key・module ID を基準に再対応付ける。

## 0. Source と secret の原則

HomeLab 独自 source は `monitoring/zabbix/` にある。Zabbix 標準 template は名前と必要バージョンだけを使い、公式配布物から復元する。secret の実値は Git に置かず、既存の Git 外 secret store（例: `../secrets`）から対象サービスの権限境界へ注入する。

|secret 種別|注入先の考え方|
|---|---|
|SNMPv3 auth/priv、device password|Zabbix host/interface の secret macro または外部 secret 管理|
|Slack webhook/token|Zabbix Media type の secret parameter|
|Zabbix API token|一時的な管理端末/CI の環境でのみ使用し、source に保存しない|
|VPN private key、CA private key|VPN Server の保護領域へ手動または secret 管理経由で配置|
|AWS credential|AWS 標準の instance role/外部 secret provider|

## 1. OS とパッケージ

|工程|source / destination|確認|STOP / rollback|
|---|---|---|---|
|OS準備|実測 baseline: Zabbix Server Debian 13 aarch64、VPN Server Ubuntu 24.04 x86_64|OS、kernel、architecture を read-only 確認|OS/architecture が異なる場合は package 手順を再評価|
|Zabbix package|公式 Zabbix 7.0.30 repository; Server は `zabbix-server-pgsql`, frontend, SQL scripts, nginx, PHP、VPN は Agent2 7.0.30|package version を固定確認|異なる major version では import 前に停止|
|DB/Web|PostgreSQL 17.11、nginx 1.26、PHP 8.4（実測）|DB schema version、PHP extensions、nginx virtual host を確認|DB restore は別承認。既存 DB を上書きしない|
|strongSwan/runtime|VPN Server strongSwan 5.9.13、systemd 255、Python 3.12.3|`swanctl --version`、systemd/package version|VPN/PKI を変更せず不足 package を報告|

## 2. Zabbix 基盤

1. 公式の Zabbix 7.0 template と SQL を導入し、Server/frontend/DB の互換性を確認する。
2. [hosts.json](monitoring.md) の8ホストを、既存の host 名で作成する。host ID は再利用しない。
3. 各 host の interface 種別・SNMP interface・ICMP/agent interface を設定する。SNMPv3 secret は外部注入する。
4. 標準 template は名前でリンクする。対象は Linux by Zabbix agent、Zabbix server health、Linux by Zabbix agent active、ICMP Ping、Mikrotik by SNMP、Cisco IOS by SNMP、Network Generic Device by SNMP など、inventory に記録されたものとする。
5. `monitoring/zabbix/templates/catalyst-1300-snmp.json` を sanitized import source として復元し、template 名 `Template HomeLab Catalyst 1300 by SNMP` と実機応答済み OID/key を確認する。QNAP は既存の `monitoring/zabbix/templates/qnap-nas-snmp.json` を使う。

Verification: template/item/trigger が enabled で、unsupported が新規発生しないこと。Rollback: import を中止し、既存 template を変更しない。

独自 template JSON は import 前にレビューし、Zabbix API token や secret macro の実値がないことを確認する。Zabbix 内部の template/item/trigger ID は export の記録値を説明用にのみ扱い、復元時の参照には使わない。

## 3. VPN collector

|source|destination|required permission|
|---|---|---|
|`monitoring/zabbix/collector/homelab-vpn-collector.py`|`/opt/homelab/example`|root:root、実行可能（unit は root 実行）|
|`collector/systemd/homelab-vpn-collector.service`|`/opt/homelab/example`|root:root、0644|
|`collector/systemd/homelab-vpn-collector.timer`|`/opt/homelab/example`|root:root、0644|
|`collector/agent2/production-vpn-active.conf`|`/opt/homelab/example`|root:root、0644（secret は含めない）|
|`collector/logrotate/homelab-vpn-monitor`|`/opt/homelab/example`|root:root、0644|

collector は `/opt/homelab/example --list-sas` と `/run/example-vici.sock` を read-only で参照し、`/opt/homelab/example`、site/remote state、event-state、`/opt/homelab/example/*.log` を生成・更新する。runtime data は Git 管理しない。unit の `ProtectSystem=strict`、既存 `ReadWritePaths`、`ReadWritePaths=/opt/homelab/example`、`NoNewPrivileges` 等の hardening を維持する。

初期化時は以下を作成し、collector の service user/group と一致させる。

```text
/opt/homelab/example     root:zabbix 0750
/opt/homelab/example     root:zabbix 0750
state JSON                       root:*      0600
event log                        root:zabbix 0640
```

timer は boot 後30秒、以後30秒周期。Agent2 は `Server=127.0.0.1`、`ServerActive=10.10.0.254:10051` と custom active keys を使う。logrotate は daily/dateext/30 世代、rename/create（copytruncate なし）である。

Verification: `python3 -m ast` 相当の構文確認、`systemctl is-enabled/is-active`、Agent2 の設定検証、status JSON の freshness、既存 Items 20001〜20003 の値を確認する。collector 実行・VPN操作・service reload は復旧作業の承認なしに行わない。

## 4. VPN Items/Triggers と frontend modules

`monitoring/zabbix/inventory/vpn-server-items-20001-20003.json` の key を名前で再作成する。status JSON は master item、dependent item、freshness item として構成され、event log は `logrt[]` の Log item である。item ID は固定しない。

以下を `/opt/homelab/example/` 配下へ配置する。

- `remote_access_sessions`
- `site_to_site_sessions`
- `vpn_connection_log`

manifest、Widget.php、form/view/action/assets の構成は repository の module directory を source とする。Zabbix frontend の module registry で有効化し、既存 Dashboard を直接上書きせず、名前・item key を照合して相当 widget を再作成する。

module directory は frontend が読める所有者・モード（通常は root 所有、directory 0755、source 0644）で配置し、既存 module を上書きしない。`php -l`、manifest JSON parse、frontend の module registry 確認を行う。登録失敗や既存 module 差分が出た場合は有効化を止めて rollback する。collector module と異なり、frontend module は runtime state/log を生成しない。

## 5. Dashboard / Slack

`monitoring/zabbix/dashboards/home-lab-overview-30001.json` は Dashboard 30001 の sanitized payload である。30001、widget、host、item、template、action ID は新環境では変化するため、widget type/name と item key、host 名で対応付ける。9 widget の配置・サイズ・source は export を参照する。

Slack は `monitoring/zabbix/actions/slack-actions.json` の Warning（Warning）/Immediate（Average 以上）と Problem/Recovery operation を再構成し、Media type の secret parameter は外部から注入する。default message に host、problem、severity、時刻、recovery 区別が含まれることを read-only 確認する。

## 6. 例外と最終監査

既知例外は [`monitoring/zabbix/known-exceptions/README.md`](security.md) を確認する。Zabbix Server optional process 12件、VPN の ens5、Catalyst の phantom LLD 6件、Catalyst Memory/Fan/CPU threshold の意図的非監視、AP の ICMP-only は自動的に削除しない。

最後に各 host で Item 値、Trigger expression、Problem、Action の severity 条件、Problem/Recovery operation、Slack delivery を静的または安全な既存履歴で確認する。実障害を発生させる E2E テストは行わない。
