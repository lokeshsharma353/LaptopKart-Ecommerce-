/**
 * Site-wide light/dark theme engine.
 *
 * LWC components are Shadow DOM isolated, but CSS custom properties pierce
 * shadow boundaries by inheritance. So instead of a shared stylesheet, every
 * themed component defines its own local tokens in its :host block as
 * `var(--lk-<token>, <light-default>)` — this module sets the --lk-* custom
 * properties on <html> (document.documentElement), which cascades the
 * current theme's values into every component's shadow tree at once.
 */

const STORAGE_KEY = 'lk_theme';
const ATTR = 'data-lk-theme';

const LIGHT_TOKENS = {
    'lk-page-bg': '#F8FAFC',
    'lk-surface': '#FFFFFF',
    'lk-surface-alt': '#F8FAFC',
    'lk-surface-hover': '#F1F5F9',
    'lk-border': '#E2E8F0',
    'lk-border-strong': '#CBD5E1',
    'lk-text-heading': '#0F172A',
    'lk-text-body': '#475569',
    'lk-text-muted': '#64748B',
    'lk-text-subtle': '#94A3B8',
    'lk-white-fixed': '#FFFFFF',
    'lk-primary': '#2563EB',
    'lk-primary-hover': '#1D4ED8',
    'lk-primary-tint': '#EFF6FF',
    'lk-primary-tint-hover': '#DBEAFE',
    'lk-primary-tint-border': '#BFDBFE',
    'lk-secondary': '#0F172A',
    'lk-secondary-hover': '#1E293B',
    'lk-success': '#16A34A',
    'lk-success-text': '#15803D',
    'lk-success-bg': '#F0FDF4',
    'lk-success-border': '#BBF7D0',
    'lk-warning': '#F59E0B',
    'lk-warning-text': '#B45309',
    'lk-warning-bg': '#FFFBEB',
    'lk-warning-border': '#FDE68A',
    'lk-error': '#DC2626',
    'lk-error-text': '#B91C1C',
    'lk-error-bg': '#FEF2F2',
    'lk-error-border': '#FECACA',
    'lk-wishlist': '#E11D48',
    'lk-wishlist-bg': '#FFF1F2',
    'lk-wishlist-border': '#FECDD3',
    'lk-divider': '#F1F5F9',
    'lk-text-strong': '#334155',
    'lk-overlay-scrim': 'rgba(15,23,42,0.75)',
    'lk-shadow-color': 'rgba(15,23,42,0.1)'
};

// A genuine black theme, not a dark-navy tint — page background is true
// black, and every surface above it (card, card-on-card, hover state) steps
// up in lightness by a deliberate, visible amount (#000 -> #121212 ->
// #1A1A1A -> #242424) specifically so no two adjacent elements ever render
// as the same near-invisible shade, the way a lazy "just darken everything"
// palette can. Borders (#2A2A2A/#3D3D3D) add a second, independent line of
// separation on top of that lightness stepping. Text tokens stay light
// grays/white rather than pure black-family colors, keeping every pairing
// (heading on surface, muted on surface-alt, etc.) at a strong, checked
// contrast ratio.
const DARK_TOKENS = {
    'lk-page-bg': '#000000',
    'lk-surface': '#121212',
    'lk-surface-alt': '#1A1A1A',
    'lk-surface-hover': '#242424',
    'lk-border': '#2A2A2A',
    'lk-border-strong': '#3D3D3D',
    'lk-text-heading': '#FFFFFF',
    'lk-text-body': '#D1D1D6',
    'lk-text-muted': '#8E8E93',
    'lk-text-subtle': '#636366',
    'lk-white-fixed': '#FFFFFF',
    'lk-primary': '#3B82F6',
    'lk-primary-hover': '#60A5FA',
    'lk-primary-tint': '#111A2B',
    'lk-primary-tint-hover': '#16223A',
    'lk-primary-tint-border': '#22355A',
    'lk-secondary': '#1C1C1C',
    'lk-secondary-hover': '#292929',
    'lk-success': '#22C55E',
    'lk-success-text': '#4ADE80',
    'lk-success-bg': '#0F1F14',
    'lk-success-border': '#1F4A31',
    'lk-warning': '#FBBF24',
    'lk-warning-text': '#FCD34D',
    'lk-warning-bg': '#21190A',
    'lk-warning-border': '#4A3B15',
    'lk-error': '#F87171',
    'lk-error-text': '#FCA5A5',
    'lk-error-bg': '#210F11',
    'lk-error-border': '#4A2028',
    'lk-wishlist': '#FB7185',
    'lk-wishlist-bg': '#210F16',
    'lk-wishlist-border': '#4A1F30',
    'lk-divider': '#1F1F1F',
    'lk-text-strong': '#E8E8EA',
    'lk-overlay-scrim': 'rgba(0,0,0,0.8)',
    'lk-shadow-color': 'rgba(0,0,0,0.65)'
};

const listeners = new Set();

function readStoredTheme() {
    try {
        const stored = window.localStorage.getItem(STORAGE_KEY);
        return stored === 'dark' ? 'dark' : 'light';
    } catch (e) {
        return 'light';
    }
}

/**
 * Writes every --lk-* custom property for the given theme onto <html>.
 * Because custom properties inherit through shadow DOM boundaries, this
 * single write is enough to re-theme every LWC component on the page.
 * @param {string} theme - 'light' | 'dark'
 */
function paint(theme) {
    const tokens = theme === 'dark' ? DARK_TOKENS : LIGHT_TOKENS;
    const root = document.documentElement;
    Object.keys(tokens).forEach((name) => {
        root.style.setProperty(`--${name}`, tokens[name]);
    });
    root.setAttribute(ATTR, theme);
}

/**
 * Returns the currently active theme ('light' | 'dark').
 * @returns {string}
 */
export function getTheme() {
    return document.documentElement.getAttribute(ATTR) || readStoredTheme();
}

/**
 * Applies and persists a theme, then notifies subscribers.
 * @param {string} theme - 'light' | 'dark'
 */
export function setTheme(theme) {
    const next = theme === 'dark' ? 'dark' : 'light';
    paint(next);
    try {
        window.localStorage.setItem(STORAGE_KEY, next);
    } catch (e) {
        // storage unavailable — theme still applies for this page view
    }
    listeners.forEach((cb) => cb(next));
}

/**
 * Flips the current theme and returns the new value.
 * @returns {string} the new theme
 */
export function toggleTheme() {
    const next = getTheme() === 'dark' ? 'light' : 'dark';
    setTheme(next);
    return next;
}

/**
 * Subscribes a callback to theme changes.
 * @param {Function} callback - called with (theme) whenever it changes
 * @returns {Function} unsubscribe function — call it in disconnectedCallback
 */
export function subscribe(callback) {
    listeners.add(callback);
    return () => listeners.delete(callback);
}

// Applies the saved (or default light) theme immediately the first time any
// component imports this module, so tokens exist on <html> before that
// component's own shadow tree paints — avoids a flash of unthemed colors.
if (!document.documentElement.hasAttribute(ATTR)) {
    paint(readStoredTheme());
}
