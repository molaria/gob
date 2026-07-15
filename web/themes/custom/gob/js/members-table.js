/**
 * @file
 * Members table: instant name search, column sorting, per-voice numbering.
 *
 * Uses Drupal.behaviors because the view content can arrive via BigPipe
 * after initial page load. Numbers are assigned once from the default
 * voice-part order and then travel with their rows through sort/filter,
 * so a member keeps "her" number.
 */
(function (Drupal, once) {
  'use strict';

  const SEL = {
    stamma: '.views-field-field-stamma',
    given: '.views-field-field-adress-given-name',
    family: '.views-field-field-adress-family-name',
  };

  function cellText(row, selector) {
    const cell = row.querySelector(selector);
    return cell ? cell.textContent.trim() : '';
  }

  // Insert a "number within voice part" column right after Stämma.
  function addVoiceNumbers(table) {
    const headStamma = table.querySelector('thead ' + SEL.stamma);
    if (!headStamma) {
      return;
    }
    const th = document.createElement('th');
    th.textContent = 'Nr i stämman';
    th.className = 'stamma-nr';
    headStamma.after(th);

    const counts = {};
    table.querySelectorAll('tbody tr').forEach((row) => {
      const voice = cellText(row, SEL.stamma);
      counts[voice] = (counts[voice] || 0) + 1;
      const td = document.createElement('td');
      td.className = 'stamma-nr';
      td.textContent = counts[voice];
      row.querySelector(SEL.stamma).after(td);
    });
  }

  function addSearch(table) {
    const tools = document.createElement('div');
    tools.className = 'table-tools';

    const input = document.createElement('input');
    input.type = 'search';
    input.placeholder = 'Sök namn ...';
    input.setAttribute('aria-label', 'Sök medlem på namn');

    const hits = document.createElement('span');
    hits.className = 'table-tools__hits';
    hits.setAttribute('aria-live', 'polite');

    tools.append(input, hits);
    table.before(tools);

    const rows = [...table.querySelectorAll('tbody tr')];
    input.addEventListener('input', () => {
      const q = input.value.trim().toLowerCase();
      let shown = 0;
      rows.forEach((row) => {
        const name = (cellText(row, SEL.given) + ' ' + cellText(row, SEL.family)).toLowerCase();
        const match = q === '' || name.includes(q);
        row.hidden = !match;
        if (match) {
          shown++;
        }
      });
      hits.textContent = q === '' ? '' : shown + ' av ' + rows.length;
    });
  }

  function addSorting(table) {
    const tbody = table.querySelector('tbody');
    const rows = [...tbody.querySelectorAll('tr')];
    // Default order (voice part) is the delivered DOM order.
    rows.forEach((row, i) => {
      row.dataset.defaultOrder = i;
    });

    const columns = [
      { selector: SEL.stamma, key: (row) => Number(row.dataset.defaultOrder), numeric: true },
      { selector: SEL.given, key: (row) => cellText(row, SEL.given), numeric: false },
      { selector: SEL.family, key: (row) => cellText(row, SEL.family), numeric: false },
    ];

    columns.forEach((col) => {
      const th = table.querySelector('thead ' + col.selector);
      if (!th) {
        return;
      }
      th.classList.add('sortable');
      th.setAttribute('role', 'button');
      th.setAttribute('tabindex', '0');

      const sort = () => {
        const wasAsc = th.getAttribute('aria-sort') === 'ascending';
        const dir = wasAsc ? -1 : 1;
        table.querySelectorAll('thead th[aria-sort]').forEach((other) => other.removeAttribute('aria-sort'));
        th.setAttribute('aria-sort', wasAsc ? 'descending' : 'ascending');

        [...tbody.querySelectorAll('tr')]
          .sort((a, b) => {
            const ka = col.key(a);
            const kb = col.key(b);
            return dir * (col.numeric ? ka - kb : String(ka).localeCompare(String(kb), 'sv'));
          })
          .forEach((row) => tbody.append(row));
      };

      th.addEventListener('click', sort);
      th.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault();
          sort();
        }
      });
    });

    // Voice part is the default sort: mark it.
    const defaultTh = table.querySelector('thead ' + SEL.stamma);
    if (defaultTh) {
      defaultTh.setAttribute('aria-sort', 'ascending');
    }
  }

  Drupal.behaviors.gobMembersTable = {
    attach(context) {
      once('gob-members', '.view-id-medlemmar table', context).forEach((table) => {
        addVoiceNumbers(table);
        addSearch(table);
        addSorting(table);
      });
    },
  };
})(Drupal, once);
