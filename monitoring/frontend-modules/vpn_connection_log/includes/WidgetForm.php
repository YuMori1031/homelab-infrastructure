<?php declare(strict_types = 0);
namespace Modules\VpnConnectionLog\Includes;
use Zabbix\Widgets\CWidgetForm;
use Zabbix\Widgets\Fields\CWidgetFieldMultiSelectItem;
class WidgetForm extends CWidgetForm {
	public function addFields(): self {
		return $this->addField((new CWidgetFieldMultiSelectItem('itemid', _('Event log item')))->setMultiple(false));
	}
}
