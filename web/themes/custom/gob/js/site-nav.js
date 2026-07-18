/**
 * @file
 * Hamburger toggle for the small-screen navigation overlay.
 * Plain JS: the header is rendered once per page, no BigPipe involved.
 */
(function () {
  'use strict';

  function init() {
    const toggle = document.querySelector('.nav-toggle');
    if (!toggle || toggle.dataset.navBound) {
      return;
    }
    toggle.dataset.navBound = '1';

    const root = document.documentElement;

    function setOpen(open) {
      root.classList.toggle('nav-open', open);
      toggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    }

    toggle.addEventListener('click', function () {
      setOpen(!root.classList.contains('nav-open'));
    });

    // Close on Escape and when a menu link is followed.
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape') {
        setOpen(false);
      }
    });

    document.querySelectorAll('.region-header a').forEach(function (link) {
      link.addEventListener('click', function () {
        setOpen(false);
      });
    });

    // Parents without a page render as <span>; make them reachable by
    // keyboard so focus-within can open their dropdown.
    document.querySelectorAll('.menu--main li.menu-item--expanded > span').forEach(function (span) {
      span.setAttribute('tabindex', '0');
    });
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  }
  else {
    init();
  }
})();
