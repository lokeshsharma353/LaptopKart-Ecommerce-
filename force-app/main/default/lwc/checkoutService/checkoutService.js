/** localStorage key used to pass the checkout draft between the Checkout and Payment pages. */
const STORAGE_KEY = 'techbasket_checkout_draft';

/**
 * checkoutService — bridges the Checkout page and the Payment page.
 * Because they are separate Experience Builder pages (not parent/child components),
 * the completed shipping/billing/shipping-method data is persisted here so the
 * Payment page can read it without re-collecting the information.
 */

/**
 * Saves the checkout draft (shipping address, billing address, shipping method)
 * to localStorage so the Payment page can read it after navigation.
 * @param {Object} draft - { shippingAddress, billingAddress, shippingMethod }
 */
export function saveDraft(draft) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(draft));
    } catch (e) {
        // storage unavailable — draft is lost across a full page navigation
    }
}

/**
 * Reads the checkout draft from localStorage.
 * Returns null if no draft exists or if storage is unavailable.
 * @returns {Object|null} the saved draft object, or null
 */
export function getDraft() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : null;
    } catch (e) {
        return null;
    }
}

/**
 * Removes the checkout draft from localStorage after a successful order.
 * Called by the Payment page once the order has been submitted to Salesforce.
 */
export function clearDraft() {
    try {
        window.localStorage.removeItem(STORAGE_KEY);
    } catch (e) {
        // nothing to clean up if storage was never available
    }
}

/**
 * Encodes the cart + checkout draft into a single URL-safe string so it can
 * be carried in the Payment page's navigation state, not just localStorage.
 * localStorage is per-origin — if Checkout and Payment ever resolve to
 * different domains (e.g. an unpublished preview vs. the live site), a value
 * saved by one page is invisible to the other and Payment sees an empty
 * cart. Putting the data in the URL itself sidesteps that entirely, since
 * the URL travels with the navigation regardless of origin.
 * @param {Array} cart - cart items array
 * @param {Object} draft - checkout draft (shipping/billing/shippingMethod)
 * @returns {string|null} encoded payload, or null if cart is empty
 */
export function encodeHandoff(cart, draft) {
    if (!cart || cart.length === 0) {
        return null;
    }
    try {
        return encodeURIComponent(JSON.stringify({ cart, draft }));
    } catch (e) {
        return null;
    }
}

/**
 * Decodes a payload produced by encodeHandoff.
 * @param {string} raw - the encoded state value read from CurrentPageReference
 * @returns {Object|null} { cart, draft }, or null if raw is missing/invalid
 */
export function decodeHandoff(raw) {
    if (!raw) {
        return null;
    }
    try {
        return JSON.parse(decodeURIComponent(raw));
    } catch (e) {
        return null;
    }
}