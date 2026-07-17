/**
 * @file
 * Instant filtering for catalogue views: typing hides every row that
 * does not match. Shared by the note register and the song tips.
 *
 * Uses Drupal.behaviors because the view content can arrive via
 * BigPipe after initial page load.
 */
(function (Drupal, once) {
  'use strict';

  const VIEWS = {
    'view-id-musik': { placeholder: 'Sök titel, kompositör ...', label: 'Sök i notregistret' },
    'view-id-lattips': { placeholder: 'Sök titel, kompositör ...', label: 'Sök bland tipsen' },
  };

  Drupal.behaviors.gobCatalogueFilter = {
    attach(context) {
      Object.entries(VIEWS).forEach(([cls, opts]) => {
        once('gob-catalogue-filter', '.' + cls, context).forEach((view) => {
          const content = view.querySelector('.view-content');
          if (!content) {
            return;
          }

          const tools = document.createElement('div');
          tools.className = 'table-tools';
          const input = document.createElement('input');
          input.type = 'search';
          input.placeholder = opts.placeholder;
          input.setAttribute('aria-label', opts.label);
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
      });
    },
  };
})(Drupal, once);
