<?php declare(strict_types = 0);
$view = new CWidgetView($data);
if ($data['message'] !== null) {
	$body = (new CTableInfo())->setNoDataMessage($data['message']);
}
else {
	$table = new CTableInfo();
	$table->setHeader([_('ユーザー名'), _('仮想IP'), _('接続開始時間'), _('接続経過時間')]);
	foreach ($data['rows'] as $values) {
		$table->addRow(array_map(static fn($value) => new CCol($value), $values));
	}
	$body = $table;
}
$view->addItem($body)->show();
