/**
 * @file
 * Drag-and-drop reordering of the /info cards, admin only. Pointer
 * events (not the HTML5 drag-and-drop API) so it works the same with
 * mouse, touch and pen. Only attached at all when the current user has
 * "administer nodes" - see gob_preprocess_views_view() in gob.theme,
 * which also supplies the save URL (with its route-scoped CSRF token
 * already baked in via Url::fromRoute()) through drupalSettings.
 */
(function (Drupal, drupalSettings, once) {
  'use strict';

  Drupal.behaviors.gobInfoDrag = {
    attach(context) {
      once('gob-info-drag', '.view-id-info .view-content', context).forEach((grid) => {
        let dragging = null;

        once('gob-info-drag-handle', '.info-tile__drag', grid).forEach((handle) => {
          handle.addEventListener('pointerdown', (event) => {
            event.preventDefault();
            dragging = handle.closest('.info-tile');
            dragging.classList.add('info-tile--dragging');
            dragging.setPointerCapture(event.pointerId);
          });

          handle.addEventListener('pointermove', (event) => {
            if (!dragging) {
              return;
            }
            const target = document
              .elementsFromPoint(event.clientX, event.clientY)
              .find((el) => el.classList.contains('info-tile') && el !== dragging);
            if (!target) {
              return;
            }
            const rect = target.getBoundingClientRect();
            const before = event.clientY < rect.top + rect.height / 2;
            target.parentNode.insertBefore(dragging, before ? target : target.nextSibling);
          });

          const stop = () => {
            if (!dragging) {
              return;
            }
            dragging.classList.remove('info-tile--dragging');
            dragging = null;
            saveOrder(grid);
          };
          handle.addEventListener('pointerup', stop);
          handle.addEventListener('pointercancel', stop);
        });
      });
    },
  };

  function saveOrder(grid) {
    const order = Array.from(grid.querySelectorAll('.info-tile')).map((tile) => tile.dataset.nid);
    const url = drupalSettings.gobInfoDrag && drupalSettings.gobInfoDrag.saveUrl;
    if (!url) {
      return;
    }
    fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ order }),
    });
  }
})(Drupal, drupalSettings, once);
