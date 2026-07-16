<?php

namespace Drupal\gob_attending\Service;

use Drupal\Core\Database\Connection;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Datetime\DrupalDateTime;
use Drupal\gob_attendance\AttendanceManager;
use Drupal\user\Entity\User;

/**
 * Bygger all data för GoB Attending-sidan.
 */
class AttendingService {

  public function __construct(
    protected EntityTypeManagerInterface $entityTypeManager,
    protected Connection $database,
    protected AttendanceManager $attendance,
  ) {}

  /**
   * Bygger ALL data som Twig behöver.
   */
  public function buildData(): array {
    $data = [];

    $nodes = $this->loadKalendariumNodes();
    $users = $this->loadActiveChoirMembers();

    $statusMap = $this->attendance->getStatusMap(array_keys($users), array_keys($nodes));

    foreach ($nodes as $nid => $node) {

      $rows = [
        'kommer' => [],
        'kommer_ej' => [],
        'inget_besked' => [],
      ];

      foreach ($users as $uid => $user) {
        $status = match ($statusMap[$uid][$nid] ?? NULL) {
          AttendanceManager::ATTENDING => 'kommer',
          AttendanceManager::DECLINED => 'kommer_ej',
          default => 'inget_besked',
        };
        $rows[$status][] = $this->buildUserRow($user);
      }

      foreach ($rows as $key => &$group) {
        $group = $this->sortAndNumber($group);
      }

      $data[] = [
        'title' => $node->label(),
        'date' => $node->get('field_datum')->value,
        'rows' => $rows,
      ];
    }

    return $data;
  }

  /**
   * Laddar kalendarium-noder (>= -3 dagar), korrekt indexerade på nid.
   */
  protected function loadKalendariumNodes(): array {
    $storage = $this->entityTypeManager->getStorage('node');

    $date = new DrupalDateTime('-3 days');

    $ids = $storage->getQuery()
      ->condition('type', 'kalendarium')
      ->condition('field_datum', $date->format('Y-m-d\TH:i:s'), '>=')
      ->condition('field_anmalan_mojlig', 1) // ✅ Endast noder med "Ja" (true)
      ->sort('field_datum', 'ASC')
      ->accessCheck(FALSE)
      ->execute();

    $nodes = $storage->loadMultiple($ids);

    // 🔴 KRITISK FIX: indexera på nid
    $indexed = [];
    foreach ($nodes as $node) {
      $indexed[$node->id()] = $node;
    }

    return $indexed;
  }

  /**
   * Laddar alla aktiva körmedlemmar.
   */
  protected function loadActiveChoirMembers(): array {
    $storage = $this->entityTypeManager->getStorage('user');

    $ids = $storage->getQuery()
      ->condition('status', 1)
      ->condition('roles', 'aktiv_kormedlem')
      ->accessCheck(FALSE)
      ->execute();

    return $storage->loadMultiple($ids);
  }

  /**
   * Bygger raddata för en användare.
   */
  protected function buildUserRow(User $user): array {
    $address = $user->get('field_adress')->first();

    return [
      'uid' => $user->id(),
      'realname' => $user->label(),
      'stamma' => $user->get('field_stamma')->entity?->label() ?? '',
      'stamma_weight' => $this->stammaWeight($user),
      'family' => $address?->family_name ?? '',
      'given' => $address?->given_name ?? '',
    ];
  }

  /**
   * Fast sorteringsordning för stämmor.
   */
  protected function stammaWeight(User $user): int {
    return match ($user->get('field_stamma')->entity?->label()) {
      'Sopran 1' => 1,
      'Sopran 2' => 2,
      'Alt 1' => 3,
      'Alt 2' => 4,
      'Musiker' => 5,
      'Dirigent' => 6,
      default => 99,
    };
  }

  /**
   * Sorterar och numrerar globalt + per stämma.
   */
  protected function sortAndNumber(array $rows): array {
    usort($rows, function ($a, $b) {
      return [$a['stamma_weight'], $a['family'], $a['given']]
        <=> [$b['stamma_weight'], $b['family'], $b['given']];
    });

    $out = [];
    $global = 1;
    $local = [];

    foreach ($rows as $row) {
      $key = $row['stamma'];
      $local[$key] = ($local[$key] ?? 0) + 1;

      $row['nr'] = $global++;
      $row['nr_local'] = $local[$key];
      $out[] = $row;
    }

    return $out;
  }

}
