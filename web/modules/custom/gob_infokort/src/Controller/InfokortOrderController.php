<?php

namespace Drupal\gob_infokort\Controller;

use Drupal\Core\Controller\ControllerBase;
use Symfony\Component\HttpFoundation\JsonResponse;
use Symfony\Component\HttpFoundation\Request;
use Symfony\Component\HttpKernel\Exception\BadRequestHttpException;

/**
 * Saves the drag-and-drop order of infokort nodes from /info.
 */
class InfokortOrderController extends ControllerBase {

  /**
   * Sets field_weight on each node to match the submitted order.
   */
  public function save(Request $request): JsonResponse {
    $data = json_decode($request->getContent(), TRUE);
    $order = $data['order'] ?? NULL;
    if (!is_array($order) || !$order) {
      throw new BadRequestHttpException('Ogiltig ordning.');
    }

    $storage = $this->entityTypeManager()->getStorage('node');
    $weight = 0;
    foreach ($order as $nid) {
      $node = $storage->load((int) $nid);
      if ($node && $node->bundle() === 'infokort') {
        $node->set('field_weight', $weight);
        $node->save();
      }
      $weight += 10;
    }

    return new JsonResponse(['status' => 'ok']);
  }

}
