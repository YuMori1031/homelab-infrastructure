<?php declare(strict_types = 0);
namespace Modules\SiteToSiteSessions\Actions;

use API;
use CControllerDashboardWidgetView;
use CControllerResponseData;
use DateTimeImmutable;
use DateTimeZone;
use JsonException;
use Modules\SiteToSiteSessions\Widget;

class WidgetView extends CControllerDashboardWidgetView {
	private const SNAPSHOT_ITEMID = '20001';
	private const SNAPSHOT_HOSTID = '10002';
	private const FRESHNESS_SECONDS = 180;
	private const SITES = ['site_a' => 'Site A', 'site_b' => 'Site B'];

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
			$data['message'] = _('This widget is restricted to the Site-to-Site status snapshot item.');
		}
		else {
			$items = API::Item()->get([
				'output' => ['itemid', 'hostid', 'lastvalue'],
				'itemids' => [self::SNAPSHOT_ITEMID],
				'hostids' => [self::SNAPSHOT_HOSTID],
				'preservekeys' => true
			]);
			$data = array_merge($data, $this->makeRows($items[self::SNAPSHOT_ITEMID]['lastvalue'] ?? null));
		}

		$this->setResponse(new CControllerResponseData($data));
	}

	private function unknownRows(): array {
		$rows = [];
		foreach (self::SITES as $label) {
			$rows[] = [$label, '⚪不明', '—', '—'];
		}
		return ['rows' => $rows, 'message' => null];
	}

	private function makeRows(?string $lastvalue): array {
		if ($lastvalue === null || $lastvalue === '') {
			return $this->unknownRows();
		}
		try {
			$snapshot = json_decode($lastvalue, true, 512, JSON_THROW_ON_ERROR);
		}
		catch (JsonException $e) {
			return $this->unknownRows();
		}
		if (!is_array($snapshot) || !isset($snapshot['collected_at'], $snapshot['sites'])
				|| !is_numeric($snapshot['collected_at']) || !is_array($snapshot['sites'])) {
			return $this->unknownRows();
		}
		$age = time() - (int) $snapshot['collected_at'];
		if ($age < 0 || $age > self::FRESHNESS_SECONDS) {
			return $this->unknownRows();
		}
		$rows = [];
		$tz = new DateTimeZone('Asia/Tokyo');
		foreach (self::SITES as $site => $label) {
			if (!array_key_exists($site, $snapshot['sites']) || !is_array($snapshot['sites'][$site])) {
				return $this->unknownRows();
			}
			$details = $snapshot['sites'][$site];
			$status = $details['status'] ?? null;
			if ($status === 'normal') {
				if (!isset($details['connected_since'], $details['elapsed_seconds'])
						|| !is_numeric($details['connected_since']) || !is_numeric($details['elapsed_seconds'])
						|| (int) $details['connected_since'] < 0 || (int) $details['elapsed_seconds'] < 0) {
					return $this->unknownRows();
				}
				$since = (new DateTimeImmutable('@'.(int) $details['connected_since']))->setTimezone($tz)->format('Y/m/d H:i:s');
				$elapsed = (int) $details['elapsed_seconds'];
				$rows[] = [$label, '🟢正常', $since, sprintf('%02d:%02d:%02d', intdiv($elapsed, 3600), intdiv($elapsed % 3600, 60), $elapsed % 60)];
			}
			elseif ($status === 'abnormal') {
				$rows[] = [$label, '🔴異常', '—', '—'];
			}
			else {
				return $this->unknownRows();
			}
		}
		return ['rows' => $rows, 'message' => null];
	}
}
