/**
 * @file
 * Note register: instant filtering. Typing hides every row that does
 * not match the title, credits or file labels.
 *
 * Uses Drupal.behaviors because the view content can arrive via
 * BigPipe after initial page load.
 */
(function (Drupal, once) {
  'use strict';

  Drupal.behaviors.gobNotesFilter = {
    attach(context) {
      once('gob-notes-filter', '.view-id-musik', context).forEach((view) => {
        const content = view.querySelector('.view-content');
        if (!content) {
          return;
        }

        const tools = document.createElement('div');
        tools.className = 'table-tools';
        const input = document.createElement('input');
        input.type = 'search';
        input.placeholder = 'Sök titel, kompositör ...';
        input.setAttribute('aria-label', 'Sök i notregistret');
        tools.appendChild(input);
        content.before(tools);

        const rows = [...content.querySelectorAll(':scope > .views-row')];
        input.addEventListener('input', () => {
          const needle = input.value.trim().toLowerCase();
          rows.forEach((row) => {
            row.hidden = needle !== '' && !row.textContent.toLowerCase().includes(needle);
          });
        });
      });
    },
  };
})(Drupal, once);
