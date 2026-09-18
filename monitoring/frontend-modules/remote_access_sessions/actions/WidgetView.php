<?php declare(strict_types = 0);
namespace Modules\RemoteAccessSessions\Actions;

use API;
use CControllerDashboardWidgetView;
use CControllerResponseData;
use DateTimeImmutable;
use DateTimeZone;
use JsonException;
use Modules\RemoteAccessSessions\Widget;

class WidgetView extends CControllerDashboardWidgetView {
	private const SNAPSHOT_ITEMID = '20000';
	private const FRESHNESS_SECONDS = 180;

	protected function doAction(): void {
		$data = [
			'name' => $this->getInput('name', $this->widget->getDefaultName()),
			'rows' => [],
			'message' => null,
			'user' => ['debug_mode' => $this->getDebugMode()]
		];

		$itemids = $this->fields_values['itemid'] ?? [];
		$valid_item = is_array($itemids) && count($itemids) === 1
			&& array_key_exists(0, $itemids) && is_scalar($itemids[0])
			&& (string) $itemids[0] === self::SNAPSHOT_ITEMID;
		if (!$valid_item) {
			$data['message'] = _('This widget is restricted to the Remote Access snapshot item.');
		}
		else {
			$item = API::Item()->get([
				'output' => ['itemid', 'hostid', 'value_type', 'lastvalue'],
				'itemids' => [self::SNAPSHOT_ITEMID],
				'hostids' => ['10002'],
				'preservekeys' => true
			]);
			$data = array_merge($data, $this->makeRows($item[self::SNAPSHOT_ITEMID]['lastvalue'] ?? null));
		}

		$this->setResponse(new CControllerResponseData($data));
	}

	private function makeRows(?string $lastvalue): array {
		if ($lastvalue === null || $lastvalue === '') {
			return ['rows' => [], 'message' => '⚪不明'];
		}
		try {
			$snapshot = json_decode($lastvalue, true, 512, JSON_THROW_ON_ERROR);
		}
		catch (JsonException $e) {
			return ['rows' => [], 'message' => '⚪不明'];
		}

		if (!is_array($snapshot) || !isset($snapshot['collected_at'], $snapshot['remote_access'])
				|| !is_numeric($snapshot['collected_at'])) {
			return ['rows' => [], 'message' => '⚪不明'];
		}
		$age = time() - (int) $snapshot['collected_at'];
		$remote = $snapshot['remote_access'];
		if ($age < 0 || $age > self::FRESHNESS_SECONDS || !is_array($remote)
				|| ($remote['collection_status'] ?? null) !== 'ok'
				|| !isset($remote['connected_count'], $remote['sessions'])
				|| !is_int($remote['connected_count']) || !is_array($remote['sessions'])) {
			return ['rows' => [], 'message' => '⚪不明'];
		}
		$count = $remote['connected_count'];
		if ($count < 0 || $count === 0) {
			return ['rows' => [], 'message' => '接続なし'];
		}
		if (count($remote['sessions']) !== $count) {
			return ['rows' => [], 'message' => '⚪不明'];
		}

		$rows = [];
		$tz = new DateTimeZone('Asia/Tokyo');
		foreach ($remote['sessions'] as $session) {
			if (!is_array($session) || !isset($session['user'], $session['virtual_ip'], $session['connected_since'], $session['elapsed_seconds'])
					|| !is_string($session['user']) || !is_string($session['virtual_ip'])
					|| !is_numeric($session['connected_since']) || !is_numeric($session['elapsed_seconds'])
					|| (int) $session['connected_since'] < 0 || (int) $session['elapsed_seconds'] < 0) {
				return ['rows' => [], 'message' => '⚪不明'];
			}
			$since = (new DateTimeImmutable('@'.(int) $session['connected_since']))->setTimezone($tz)->format('Y/m/d H:i:s');
			$elapsed = (int) $session['elapsed_seconds'];
			$rows[] = [$session['user'], $session['virtual_ip'], $since,
				sprintf('%02d:%02d:%02d', intdiv($elapsed, 3600), intdiv($elapsed % 3600, 60), $elapsed % 60)
			];
		}
		return ['rows' => $rows, 'message' => null];
	}
}
