<?php

namespace Drupal\gob_attending\Service;

use Drupal\Core\Database\Connection;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Datetime\DrupalDateTime;
use Drupal\user\Entity\User;

/**
 * Bygger all data för GoB Attending-sidan.
 */
class AttendingService {

  protected EntityTypeManagerInterface $entityTypeManager;
  protected Connection $database;
  protected FlagStatusResolver $resolver;

  public function __construct(
    EntityTypeManagerInterface $entityTypeManager,
    Connection $database,
    FlagStatusResolver $resolver
  ) {
    $this->entityTypeManager = $entityTypeManager;
    $this->database = $database;
    $this->resolver = $resolver;
  }

  /**
   * Bygger ALL data som Twig behöver.
   */
  public function buildData(): array {
    $data = [];

    $nodes = $this->loadKalendariumNodes();
    $users = $this->loadActiveChoirMembers();

    // 🔴 Viktigt: array_keys($nodes) är nu RIKTIGA nid
    $flagMap = $this->loadFlagMap(array_keys($users), array_keys($nodes));

    foreach ($nodes as $nid => $node) {

      $rows = [
        'kommer' => [],
        'kommer_ej' => [],
        'inget_besked' => [],
      ];

      foreach ($users as $uid => $user) {
        $flags = $flagMap[$uid][$nid] ?? [];

        // 🔍 Logg för felsökning (kan tas bort senare)
        \Drupal::logger('gob_attending')->notice(
          'Resolver input: uid=@uid nid=@nid flags=@flags',
          [
            '@uid' => $uid,
            '@nid' => $nid,
            '@flags' => print_r($flags, TRUE),
          ]
        );

        $status = $this->resolver->resolve($flags);
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
   * Bygger flaggkarta: [uid][nid][flag_id] = TRUE
   */
  protected function loadFlagMap(array $uids, array $nids): array {
    $map = [];

    if (!$uids || !$nids) {
      return $map;
    }

    // 🔍 Debug
    \Drupal::logger('gob_attending')->notice(
      'FlagMap query uids=@uids nids=@nids',
      [
        '@uids' => implode(',', $uids),
        '@nids' => implode(',', $nids),
      ]
    );

    $result = $this->database->select('flagging', 'f')
      ->fields('f', ['uid', 'entity_id', 'flag_id'])
      ->condition('uid', $uids, 'IN')
      ->condition('entity_id', $nids, 'IN')
      ->execute();

    foreach ($result as $row) {
      $map[$row->uid][$row->entity_id][$row->flag_id] = TRUE;
    }

    return $map;
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
