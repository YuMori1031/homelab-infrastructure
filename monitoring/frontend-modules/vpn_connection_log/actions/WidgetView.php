<?php declare(strict_types = 0);
namespace Modules\VpnConnectionLog\Actions;
use API;
use CControllerDashboardWidgetView;
use CControllerResponseData;
class WidgetView extends CControllerDashboardWidgetView {
	private const REMOTE_ITEMID = '20003';
	private const SITE_ITEMID = '20002';
	private const HOSTID = '10002';
	private const LIMIT = 20;
	protected function doAction(): void {
		$data = ['name' => $this->getInput('name', $this->widget->getDefaultName()), 'rows' => [], 'message' => null, 'mode' => 'remote_access', 'user' => ['debug_mode' => $this->getDebugMode()]];
		$itemids = $this->fields_values['itemid'] ?? [];
		$itemid = is_array($itemids) && count($itemids) === 1 && isset($itemids[0]) && is_scalar($itemids[0]) ? (string) $itemids[0] : '';
		$mode_values = $this->fields_values['mode'] ?? [];
		$mode = is_array($mode_values) && isset($mode_values[0]) && is_scalar($mode_values[0]) ? (string) $mode_values[0] : '';
		if ($mode === '') { $mode = $itemid === self::SITE_ITEMID ? 'site_to_site' : 'remote_access'; }
		$expected_itemid = $mode === 'site_to_site' ? self::SITE_ITEMID : ($mode === 'remote_access' ? self::REMOTE_ITEMID : '');
		$data['mode'] = $mode;
		if ($expected_itemid === '' || $itemid !== $expected_itemid) {
			$data['message'] = _('This widget is restricted to its configured VPN event log item.');
		}
		else {
			try {
				$items = API::Item()->get(['output' => ['itemid','hostid','value_type'], 'itemids' => [$expected_itemid], 'hostids' => [self::HOSTID], 'preservekeys' => true]);
				if (!isset($items[$expected_itemid])) { $data['message'] = '⚪不明'; }
				else {
					$history = API::History()->get(['output' => ['itemid','clock','ns','value'], 'history' => 2, 'itemids' => [$expected_itemid], 'sortfield' => ['clock','ns'], 'sortorder' => ZBX_SORT_DOWN, 'limit' => self::LIMIT]);
					$data['rows'] = $this->parseRows($history, $mode);
					if ($data['rows'] === [] && $history === []) { $data['message'] = '接続ログなし'; }
				}
			}
			catch (\Throwable $e) { $data['message'] = '⚪不明'; }
		}
		$this->setResponse(new CControllerResponseData($data));
	}
	private function parseRows(array $history, string $mode): array {
		$rows = [];
		$expected = $mode === 'site_to_site' ? 3 : 4;
		foreach ($history as $entry) {
			if (!isset($entry['value']) || !is_string($entry['value'])) continue;
			$parts = explode('|', $entry['value']);
			if (count($parts) !== $expected || !in_array($parts[$expected - 1], ['接続','切断'], true)) continue;
			$event = $parts[$expected - 1] === '接続' ? '🟢接続' : '🔴切断';
			$rows[] = $mode === 'site_to_site'
				? [$parts[0], $parts[1], $event]
				: [$parts[0], $parts[1], $parts[2], $event];
		}
		return $rows;
	}
}
