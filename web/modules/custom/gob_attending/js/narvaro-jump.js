/**
 * @file
 * Öppnar och scrollar till rätt händelse på /gob/narvaro när man kommer
 * från länken "Anmälda" på kalendariesidan (#nid-123 i webbadressen).
 */
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.gobNarvaroJump = {
    attach(context) {
      once('gob-narvaro-jump', 'body', context).forEach(() => {
        const hash = window.location.hash;
        if (!hash) {
          return;
        }

        const target = document.querySelector(hash);
        if (target && target.tagName === 'DETAILS') {
          target.open = true;

          // The sticky site header would otherwise cover the event's
          // summary row - measure it and leave room above the target.
          const header = document.querySelector('header[role="banner"]');
          if (header) {
            target.style.scrollMarginTop = `${header.offsetHeight + 16}px`;
          }

          target.scrollIntoView();
        }
      });
    },
  };
})(Drupal, once);
