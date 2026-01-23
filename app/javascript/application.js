// Configure your import map in config/importmap.rb. Read more: https://github.com/rails/importmap-rails
import "@hotwired/turbo-rails"
import "controllers"
import "tournament_groups_mode_form"

(function() {
  function scrollKey() {
    return "scrollY:" + window.location.pathname + window.location.search;
  }

  function saveScrollY() {
    try {
      window.sessionStorage.setItem(scrollKey(), String(window.scrollY || 0));
    } catch (e) {
    }
  }

  function restoreScrollY() {
    var y;
    try {
      y = window.sessionStorage.getItem(scrollKey());
    } catch (e) {
      y = null;
    }
    if (y == null) return;

    var parsed = parseInt(y, 10);
    if (Number.isNaN(parsed)) return;

    window.requestAnimationFrame(function() {
      window.requestAnimationFrame(function() {
        window.scrollTo(0, parsed);
      });
    });
  }

  document.addEventListener("submit", function() {
    saveScrollY();
  }, true);

  document.addEventListener("turbo:before-visit", function() {
    saveScrollY();
  });

  window.addEventListener("pagehide", function() {
    saveScrollY();
  });

  document.addEventListener("turbo:load", function() {
    restoreScrollY();
  });

  document.addEventListener("DOMContentLoaded", function() {
    restoreScrollY();
  });

  window.addEventListener("pageshow", function() {
    restoreScrollY();
  });
})();
