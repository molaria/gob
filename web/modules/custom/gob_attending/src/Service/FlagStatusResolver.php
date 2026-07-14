<?php

namespace Drupal\gob_attending\Service;

class FlagStatusResolver {

  /**
   * Avgör deltagarstatus baserat på flaggor.
   *
   * Tillåtna kombinationer:
   *
   * deltar + !deltar_andrad           = kommer
   * deltar + deltar_andrad            = kommer_ej
   * deltar_ej + !delta_ej_andrad      = kommer_ej
   * deltar_ej + delta_ej_andrad       = kommer
   */
  public function resolve(array $flags): string {

    // DEBUG – kan tas bort senare
//    \Drupal::logger('gob_attending')->notice(
//      'Resolver flags: @flags',
//      ['@flags' => implode(', ', array_keys($flags))]
//    );

    // 🔑 FLAGGOR – exakt samma namn som i databasen
    $deltar = !empty($flags['deltar']);
    $deltar_andrad = !empty($flags['deltar_andrad']);

    $deltar_ej = !empty($flags['deltar_ej']);
    $delta_ej_andrad = !empty($flags['delta_ej_andrad']);

    // ---- LOGIK ----

    if ($deltar && !$deltar_andrad) {
      return 'kommer';
    }

    if ($deltar && $deltar_andrad) {
      return 'kommer_ej';
    }

    if ($deltar_ej && !$delta_ej_andrad) {
      return 'kommer_ej';
    }

    if ($deltar_ej && $delta_ej_andrad) {
      return 'kommer';
    }

    return 'inget_besked';
  }

}
