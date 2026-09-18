/** localStorage key used to persist notification preferences across visits. */
const STORAGE_KEY = 'techbasket_account_settings';

/** Default preferences used the first time a shopper opens Account Settings. */
const DEFAULTS = {
    emailNotifications: true
};

/**
 * Returns the saved notification preferences, merged over the defaults so a
 * newly-added preference always has a sensible value even for a shopper who
 * saved settings before it existed.
 * @returns {Object} { emailNotifications }
 */
export function getSettings() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? { ...DEFAULTS, ...JSON.parse(raw) } : { ...DEFAULTS };
    } catch (e) {
        return { ...DEFAULTS };
    }
}

/**
 * Persists notification preferences.
 * @param {Object} settings - { emailNotifications }
 */
export function saveSettings(settings) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(settings));
    } catch (e) {
        // storage unavailable — state stays in-memory for this session
    }
}
