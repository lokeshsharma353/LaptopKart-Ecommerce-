/** localStorage key used to persist the logged-in session across page navigations. */
const STORAGE_KEY = 'techbasket_session';
/** Set of subscriber callbacks notified whenever the session changes. */
const listeners = new Set();

/**
 * Reads the session from localStorage.
 * Returns null if storage is unavailable, empty, or the data is corrupt.
 * @returns {Object|null} { id, name, email, phone } or null when logged out
 */
function readSession() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (e) {
        return null;
    }
}

/**
 * Persists the session to localStorage (or clears it) and notifies subscribers.
 * Silently skips the write if storage is unavailable.
 * @param {Object|null} session - session object to store, or null to clear it
 */
function writeSession(session) {
    try {
        if (session) {
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify(session));
        } else {
            window.localStorage.removeItem(STORAGE_KEY);
        }
    } catch (e) {
        // storage unavailable — state stays in-memory for this session
    }
    listeners.forEach((cb) => cb(session));
}

/**
 * Returns the current session, or null if nobody is logged in.
 * This is a lightweight, client-side-only session (this storefront has no
 * real per-shopper Salesforce login — every visitor is the Site Guest User).
 * It is set after a successful LoginCredentialsController.signUp/logIn call
 * and is not itself a security boundary — treat it as a UI convenience, not
 * real authentication.
 * @returns {Object|null} { id, name, email, phone } or null
 */
export function getSession() {
    return readSession();
}

/**
 * True when a session is currently stored (i.e. the shopper is "logged in").
 * @returns {boolean}
 */
export function isLoggedIn() {
    return readSession() !== null;
}

/**
 * Starts a session after a successful sign-up or login call.
 * @param {Object} session - { id, name, email, phone } returned by LoginCredentialsController
 */
export function setSession(session) {
    writeSession(session);
}

/**
 * Ends the current session (logout).
 */
export function clearSession() {
    writeSession(null);
}

/**
 * Subscribes a callback to session change events.
 * The callback is called with the new session (or null) after every change.
 * @param {Function} callback - called with (session) on every change
 * @returns {Function} unsubscribe function — call it in disconnectedCallback
 */
export function subscribe(callback) {
    listeners.add(callback);
    return () => listeners.delete(callback);
}
