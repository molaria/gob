<?php

namespace Drupal\kalendarium_deltagande\Plugin\views\field;

use Drupal\views\Plugin\views\field\FieldPluginBase;
use Drupal\views\ResultRow;

/**
 * @ViewsField("deltagande_knapp")
 */
class DeltagandeKnapp extends FieldPluginBase {

  public function render(ResultRow $row) {
    $node = $row->_entity;
    $user = \Drupal::currentUser();

    $flag_service = \Drupal::service('flag');
    $flag_deltar = $flag_service->getFlagById('participation');
    $flag_deltar_inte = $flag_service->getFlagById('jag_deltar_inte');

    $is_deltar = $flag_deltar->getFlagging($node, $user);
    $is_deltar_inte = $flag_deltar_inte->getFlagging($node, $user);

    $output = '';

    if (!$is_deltar && !$is_deltar_inte) {
      $output .= '<div class="deltagande-knapp">';
      $output .= '<a href="/flag/flag/participation/node/' . $node->id() . '" class="btn btn-success">Jag deltar</a>';
      $output .= '<a href="/flag/flag/jag_deltar_inte/node/' . $node->id() . '" class="btn btn-danger">Jag deltar inte</a>';
      $output .= '</div>';
    }
    elseif ($is_deltar) {
      $output .= '<a href="/flag/unflag/participation/node/' . $node->id() . '" class="btn btn-warning">Avanmäl</a>';
    }
    elseif ($is_deltar_inte) {
      $output .= '<a href="/flag/unflag/jag_deltar_inte/node/' . $node->id() . '" class="btn btn-primary">Anmäl</a>';
    }

    return [
      '#markup' => $output,
      '#allowed_tags' => ['a', 'div'],
    ];
  }
}
