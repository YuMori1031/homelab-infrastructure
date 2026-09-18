<?php declare(strict_types = 0);
namespace Modules\VpnConnectionLog;
use Zabbix\Core\CWidget;
class Widget extends CWidget {
	public function getDefaultName(): string { return _('VPN接続ログ（Remote Access）'); }
}
