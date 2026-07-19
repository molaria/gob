/**
 * @file
 * In-place updates for the kalendarium answer buttons (attendance and
 * fika). Clicking a button fetches the server-rendered calendar page in
 * the background and swaps in the fresh row, so the visitor never loses
 * scroll position or accordion state. Progressive enhancement: without
 * JS, or on any error, the links keep working as full page loads.
 */
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.gobAttendanceAjax = {
    attach(context) {
      once('att-ajax', '.cal-acc .att-btn', context).forEach((link) => {
        link.addEventListener('click', async (event) => {
          const row = link.closest('.cal-acc');
          if (!row || !row.dataset.nid) {
            return;
          }
          // preventDefault also stops the <summary> from toggling when
          // a button inside it is clicked.
          event.preventDefault();
          if (row.getAttribute('aria-busy') === 'true') {
            return;
          }
          row.setAttribute('aria-busy', 'true');

          try {
            const response = await fetch(link.href, { credentials: 'same-origin' });
            if (!response.ok) {
              throw new Error(`HTTP ${response.status}`);
            }
            const doc = new DOMParser().parseFromString(await response.text(), 'text/html');
            const fresh = doc.querySelector(`.cal-acc[data-nid="${row.dataset.nid}"]`);
            if (!fresh) {
              throw new Error('row missing in response');
            }
            // Keep the accordion the way the visitor left it.
            fresh.toggleAttribute('open', row.open);
            row.replaceWith(fresh);
            Drupal.attachBehaviors(fresh);
          }
          catch (error) {
            // Fall back to the ordinary full page load.
            window.location.href = link.href;
          }
        });
      });
    },
  };
})(Drupal, once);
