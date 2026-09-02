<?php

namespace Drupal\gob_attending\Service;

use Drupal\Core\Database\Connection;
use Drupal\Core\Datetime\DateFormatterInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Datetime\DrupalDateTime;
use Drupal\gob_attendance\AttendanceManager;
use Drupal\user\Entity\User;

/**
 * Bygger all data för GoB Attending-sidan.
 */
class AttendingService {

  /**
   * Uid:n som aldrig ska synas i SMS-telefonlistan (kopieringsvänlig lista
   * längst ner under "Saknar besked"), även om de saknar besked
   * (Bror Engstrom, Mats-Olof Liljegren, Stefan Berglund).
   */
  protected const EXCLUDED_FROM_PHONE_LIST = [17, 19, 82];

  public function __construct(
    protected EntityTypeManagerInterface $entityTypeManager,
    protected Connection $database,
    protected AttendanceManager $attendance,
    protected DateFormatterInterface $dateFormatter,
  ) {}

  /**
   * Bygger ALL data som Twig behöver.
   *
   * @param bool $past
   *   FALSE för kommande händelser (idag och framåt, samma gräns som
   *   /kalendarium), TRUE för tidigare händelser (strikt före idag).
   */
  public function buildData(bool $past = FALSE): array {
    $data = [];

    $nodes = $past ? $this->loadPastKalendariumNodes() : $this->loadKalendariumNodes();
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

      $missingPhones = [];
      foreach ($rows['inget_besked'] as $row) {
        if (!in_array((int) $row['uid'], self::EXCLUDED_FROM_PHONE_LIST, TRUE) && $row['phone'] !== '') {
          $missingPhones[] = $row['phone'];
        }
      }

      foreach ($rows as $key => &$group) {
        $group = $this->sortAndNumber($group);
      }
      unset($group);

      $timestamp = $node->get('field_datum')->date?->getTimestamp() ?? time();

      $data[] = [
        'title' => $node->label(),
        'date' => $this->dateFormatter->format($timestamp, 'gob_weekday_date'),
        'time' => $this->dateFormatter->format($timestamp, 'gob_time'),
        'counts' => [
          'kommer' => count($rows['kommer']),
          'kommer_ej' => count($rows['kommer_ej']),
          'inget_besked' => count($rows['inget_besked']),
        ],
        'rows' => $rows,
        // Ett nummer per rad i en egen kolumn - enkelt att markera och
        // kopiera för att klistra in i t.ex. Meddelanden.
        'missing_phones' => $missingPhones,
      ];
    }

    return $data;
  }

  /**
   * Laddar kommande kalendarium-noder (idag och framåt), indexerade på nid.
   *
   * Samma gräns som /kalendarium ("Today" - midnatt idag).
   */
  protected function loadKalendariumNodes(): array {
    return $this->queryKalendariumNodes('>=', 'ASC');
  }

  /**
   * Laddar tidigare kalendarium-noder (strikt före idag), fallande.
   */
  protected function loadPastKalendariumNodes(): array {
    return $this->queryKalendariumNodes('<', 'DESC');
  }

  /**
   * Gemensam fråga för kommande/tidigare-listorna.
   */
  protected function queryKalendariumNodes(string $operator, string $sortDirection): array {
    $storage = $this->entityTypeManager->getStorage('node');

    $date = new DrupalDateTime('today');

    $ids = $storage->getQuery()
      ->condition('type', 'kalendarium')
      ->condition('field_datum', $date->format('Y-m-d\TH:i:s'), $operator)
      ->condition('field_anmalan_mojlig', 1) // ✅ Endast noder med "Ja" (true)
      ->sort('field_datum', $sortDirection)
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
      'phone' => $user->get('field_telefonnummer')->value ?? '',
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
