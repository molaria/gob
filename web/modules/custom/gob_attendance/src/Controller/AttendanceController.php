<?php

namespace Drupal\gob_attendance\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\Core\Routing\RedirectDestinationInterface;
use Drupal\gob_attendance\AttendanceManager;
use Drupal\node\NodeInterface;
use Symfony\Component\DependencyInjection\ContainerInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpKernel\Exception\AccessDeniedHttpException;

/**
 * Records attendance answers from the kalendarium buttons.
 */
class AttendanceController extends ControllerBase {

  public function __construct(
    protected AttendanceManager $manager,
    protected RedirectDestinationInterface $destination,
  ) {}

  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('gob_attendance.manager'),
      $container->get('redirect.destination'),
    );
  }

  /**
   * Saves the answer and returns to the calendar with a confirmation.
   */
  public function set(NodeInterface $node, string $answer): RedirectResponse {
    if ($node->bundle() !== 'kalendarium' || $node->get('field_anmalan_mojlig')->value != 1) {
      throw new AccessDeniedHttpException();
    }

    $status = $answer === 'ja' ? AttendanceManager::ATTENDING : AttendanceManager::DECLINED;
    $previous = $this->manager->setStatus((int) $this->currentUser()->id(), (int) $node->id(), $status);

    $state_text = $status === AttendanceManager::ATTENDING ? 'du är anmäld' : 'du är avanmäld';
    if ($previous === NULL) {
      $this->messenger()->addStatus("Tack för ditt besked: $state_text.");
    }
    elseif ($previous !== $status) {
      $this->messenger()->addStatus("Ditt svar är ändrat: $state_text.");
    }
    else {
      $this->messenger()->addStatus("Ditt besked står kvar: $state_text.");
    }

    return new RedirectResponse($this->destination->get() ?: '/kalendarium');
  }

}
