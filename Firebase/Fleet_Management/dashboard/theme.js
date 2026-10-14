(() => {
  const storageKey = 'navride-fleet-theme';

  function applyTheme(value) {
    const theme = value === 'light' ? 'light' : 'dark';
    document.documentElement.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]').content =
      getComputedStyle(document.documentElement).getPropertyValue('--canvas').trim();
    document.getElementById('theme-toggle')?.setAttribute('aria-checked', String(theme === 'dark'));
  }

  let savedTheme;
  try { savedTheme = localStorage.getItem(storageKey); } catch { /* Storage may be blocked. */ }
  applyTheme(savedTheme);

  document.addEventListener('DOMContentLoaded', () => {
    applyTheme(document.documentElement.dataset.theme);
    document.getElementById('theme-toggle').addEventListener('click', () => {
      const theme = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
      applyTheme(theme);
      try { localStorage.setItem(storageKey, theme); } catch { /* Keep the choice for this page. */ }
    });
  });

  window.addEventListener('storage', (event) => {
    if (event.key === storageKey || event.key === null) applyTheme(event.newValue);
  });
})();
