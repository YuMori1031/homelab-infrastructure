<?php declare(strict_types = 0);
$view = new CWidgetView($data);
if ($data['message'] !== null) {
	$body = (new CTableInfo())->setNoDataMessage($data['message']);
}
else {
	$table = new CTableInfo();
	$table->setHeader($data['mode'] === 'site_to_site'
		? [_('日時'), _('拠点'), _('イベント')]
		: [_('日時'), _('ユーザー名'), _('仮想IP'), _('イベント')]
	);
	foreach ($data['rows'] as $values) { $table->addRow(array_map(static fn($value) => new CCol($value), $values)); }
	$body = $table;
}
$view->addItem($body)->show();
