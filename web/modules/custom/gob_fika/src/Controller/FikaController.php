<?php

namespace Drupal\gob_fika\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Routing\RedirectDestinationInterface;
use Drupal\node\NodeInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * Adds or removes the current user in field_fikafixare.
 *
 * The route never takes a user parameter: members can only ever act
 * on themselves, by construction.
 */
class FikaController extends ControllerBase {

  public function __construct(
    protected RedirectDestinationInterface $destination,
  ) {}

  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('redirect.destination'),
    );
  }

  /**
   * Saves the answer and returns to the calendar with a confirmation.
   */
  public function set(NodeInterface $node, string $answer): RedirectResponse {
    // Same gate as the fika section in the row template.
    if ($node->bundle() !== 'kalendarium' || $node->get('field_anmalan_mojlig')->value != 1) {
      throw new AccessDeniedHttpException();
    }

    $uid = (int) $this->currentUser()->id();
    $field = $node->get('field_fikafixare');
    $uids = array_map(static fn (array $item): int => (int) $item['target_id'], $field->getValue());

    if ($answer === 'ja') {
      if (!in_array($uid, $uids, TRUE)) {
        $field->appendItem($uid);
        $node->save();
        $this->messenger()->addStatus('Tack, du står nu för fikat.');
      }
      else {
        $this->messenger()->addStatus('Du står redan för fikat.');
      }
    }
    else {
      if (in_array($uid, $uids, TRUE)) {
        $field->setValue(array_values(array_filter(
          $field->getValue(),
          static fn (array $item): bool => (int) $item['target_id'] !== $uid,
        )));
        $node->save();
        $this->messenger()->addStatus('Du är borttagen från fikalistan.');
      }
      else {
        $this->messenger()->addStatus('Du stod inte på fikalistan.');
      }
    }

    return new RedirectResponse($this->destination->get() ?: '/kalendarium');
  }

}
