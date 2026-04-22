// ── auth.js — Access key authentication guard ──────────────────────────────
//
// Responsibilities:
// - Prompt user for access key when server requires one
// - Cache key in localStorage; pass via Authorization header
// - Block app boot until auth passes
// ─────────────────────────────────────────────────────────────────────────
const Auth = (() => {
  let _authCheckPromise = null;
  let _authPassed = false;

  async function check() {
    if (_authCheckPromise) return _authCheckPromise;
    _authCheckPromise = _doCheck();
    return _authCheckPromise;
  }

  async function _doCheck() {
    const key = _getStoredKey();

    // Always probe first — server may not require auth at all (e.g. localhost).
    try {
      const r = await fetch('/api/sessions?limit=1', {
        headers: key ? { 'Authorization': `Bearer ${key}` } : {}
      });

      if (r.ok) {
        _authPassed = true;
        return true;
      }

      if (r.status === 401) {
        // Server requires auth — prompt for key.
        localStorage.removeItem('clacky_access_key');
        return await _promptAndRetry();
      }

      // Other errors (5xx etc.) — let the app proceed.
      _authPassed = true;
      return true;
    } catch {
      // Network error — let the app proceed.
      _authPassed = true;
      return true;
    }
  }

  async function _promptAndRetry() {
    const message = (typeof I18n !== 'undefined')
      ? I18n.t('auth.accessKeyRequired')
      : 'Access key required:';

    const inputKey = (typeof Modal !== 'undefined' && Modal.prompt)
      ? await Modal.prompt(message)
      : prompt(message);

    if (!inputKey || !inputKey.trim()) {
      _authPassed = false;
      return false;
    }

    const trimmed = inputKey.trim();
    localStorage.setItem('clacky_access_key', trimmed);

    // Validate the newly entered key without reloading.
    try {
      const r = await fetch('/api/sessions?limit=1', {
        headers: { 'Authorization': `Bearer ${trimmed}` }
      });
      if (r.ok) {
        _authPassed = true;
        return true;
      }
      // Still wrong — clear storage and restart the auth flow.
      localStorage.removeItem('clacky_access_key');
      _authCheckPromise = null;
      return check();
    } catch {
      _authPassed = true;
      return true;
    }
  }

  function _getStoredKey() {
    return localStorage.getItem('clacky_access_key') ||
      new URLSearchParams(location.search).get('access_key') || null;
  }

  function getHeaders() {
    const key = _getStoredKey();
    return key ? { 'Authorization': `Bearer ${key}` } : {};
  }

  return {
    check,
    getHeaders,
    getKey: _getStoredKey,
    reset() { _authCheckPromise = null; },
    get passed() { return _authPassed; }
  };
})();
