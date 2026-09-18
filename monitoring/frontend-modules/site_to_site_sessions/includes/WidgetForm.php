<?php declare(strict_types = 0);
namespace Modules\SiteToSiteSessions\Includes;

use Zabbix\Widgets\CWidgetForm;
use Zabbix\Widgets\Fields\CWidgetFieldMultiSelectItem;

class WidgetForm extends CWidgetForm {
	public function addFields(): self {
		return $this->addField(
			(new CWidgetFieldMultiSelectItem('itemid', _('Status snapshot item')))->setMultiple(false)
		);
	}
}
