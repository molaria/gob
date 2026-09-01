<?php

namespace Drupal\gob_attending\Controller;

use Drupal\Core\Controller\ControllerBase;
use Drupal\gob_attending\Service\AttendingService;
use Symfony\Component\DependencyInjection\ContainerInterface;

class AttendingController extends ControllerBase {

  protected AttendingService $service;

  public function __construct(AttendingService $service) {
    $this->service = $service;
  }

  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('gob_attending.attending_service')
    );
  }

  public function page(): array {
    return $this->buildPage(FALSE);
  }

  public function pastPage(): array {
    return $this->buildPage(TRUE);
  }

  protected function buildPage(bool $past): array {
    return [
      '#theme' => 'gob_attending_page',
      '#data' => $this->service->buildData($past),
      '#past' => $past,
      '#attached' => [
        'library' => ['gob/kalendarium'],
      ],
      '#cache' => [
        'contexts' => ['user.roles'],
        'max-age' => 0,
      ],
    ];
  }

}
