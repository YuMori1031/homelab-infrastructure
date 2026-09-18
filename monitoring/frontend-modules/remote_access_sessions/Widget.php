<?php declare(strict_types = 0);
namespace Modules\RemoteAccessSessions;

use Zabbix\Core\CWidget;

class Widget extends CWidget {
	public function getDefaultName(): string {
		return _('VPN接続状況（Remote Access）');
	}
}
