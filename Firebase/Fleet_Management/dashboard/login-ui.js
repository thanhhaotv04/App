document.addEventListener('DOMContentLoaded', () => {
  const password = document.getElementById('password');
  const toggle = document.getElementById('password-toggle');
  const message = document.getElementById('auth-startup');
  const retry = document.getElementById('retry-auth');

  function unavailable() {
    message.hidden = false;
    message.textContent = 'Sign-in service is unavailable. Check your connection and reload.';
    retry.hidden = false;
  }

  function ready() {
    clearTimeout(startupTimeout);
    message.hidden = true;
    retry.hidden = true;
  }

  const startupTimeout = setTimeout(() => {
    if (!window.navrideAuthReady) unavailable();
  }, 15_000);
  window.addEventListener('navride-auth-ready', ready);
  if (window.navrideAuthReady) ready();
  retry.addEventListener('click', () => window.location.reload());

  function setVisible(visible) {
    password.type = visible ? 'text' : 'password';
    toggle.textContent = visible ? 'Hide' : 'Show';
    toggle.setAttribute('aria-label', visible ? 'Hide password' : 'Show password');
  }

  toggle.addEventListener('click', () => setVisible(password.type === 'password'));
  document.getElementById('login-form').addEventListener('submit', (event) => {
    // Never submit credentials as a native form while Firebase is still loading.
    event.preventDefault();
    setVisible(false);
    if (!window.navrideAuthReady) unavailable();
  });
});
