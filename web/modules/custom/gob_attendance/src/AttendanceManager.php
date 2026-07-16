<?php

namespace Drupal\gob_attendance;

use Drupal\Component\Datetime\TimeInterface;
use Drupal\Core\Database\Connection;

/**
 * Reads and writes attendance answers.
 *
 * Statuses are 'attending' and 'declined'; the absence of a row means
 * the member has not answered yet (NULL from the getters).
 */
class AttendanceManager {

  public const ATTENDING = 'attending';
  public const DECLINED = 'declined';

  public function __construct(
    protected Connection $database,
    protected TimeInterface $time,
  ) {}

  /**
   * Returns the member's status for an event, or NULL for no answer.
   */
  public function getStatus(int $uid, int $nid): ?string {
    $status = $this->database->select('gob_attendance', 'a')
      ->fields('a', ['status'])
      ->condition('uid', $uid)
      ->condition('nid', $nid)
      ->execute()
      ->fetchField();
    return $status === FALSE ? NULL : $status;
  }

  /**
   * Saves an answer and returns the previous status (NULL if first answer).
   */
  public function setStatus(int $uid, int $nid, string $status): ?string {
    if (!in_array($status, [self::ATTENDING, self::DECLINED], TRUE)) {
      throw new \InvalidArgumentException("Okänd status: $status");
    }
    $previous = $this->getStatus($uid, $nid);
    $this->database->merge('gob_attendance')
      ->keys(['uid' => $uid, 'nid' => $nid])
      ->fields(['status' => $status, 'changed' => $this->time->getRequestTime()])
      ->execute();
    return $previous;
  }

  /**
   * Status map for many members and events: [uid][nid] => status.
   */
  public function getStatusMap(array $uids, array $nids): array {
    $map = [];
    if (!$uids || !$nids) {
      return $map;
    }
    $result = $this->database->select('gob_attendance', 'a')
      ->fields('a', ['uid', 'nid', 'status'])
      ->condition('uid', $uids, 'IN')
      ->condition('nid', $nids, 'IN')
      ->execute();
    foreach ($result as $row) {
      $map[$row->uid][$row->nid] = $row->status;
    }
    return $map;
  }

}
