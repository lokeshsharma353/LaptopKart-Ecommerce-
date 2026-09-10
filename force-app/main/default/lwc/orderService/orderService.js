import getOrders from '@salesforce/apex/CheckoutController.getOrders';
import getOrdersByEmail from '@salesforce/apex/CheckoutController.getOrdersByEmail';
import cancelOrderApex from '@salesforce/apex/CheckoutController.cancelOrder';

/**
 * orderService — tracks which Salesforce Order Ids this browser has placed.
 * Until real user authentication is wired up, Order Ids are stored locally
 * so Order History / Tracking / Confirmation know which records to fetch from Apex.
 */
const STORAGE_KEY = 'techbasket_order_ids';
/** localStorage key for the last email used at checkout — see getMyOrders. */
const EMAIL_STORAGE_KEY = 'techbasket_customer_email';

/**
 * Reads the stored Order Id array from localStorage.
 * Returns an empty array if storage is unavailable or the data is corrupt.
 * @returns {string[]} array of Salesforce Order Ids, newest first
 */
function readIds() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

/**
 * Persists the Order Id array to localStorage.
 * Silently skips the write if storage is unavailable.
 * @param {string[]} ids - array of Salesforce Order Ids
 */
function writeIds(ids) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(ids));
    } catch (e) {
        // storage unavailable — the order still exists in Salesforce either way
    }
}

/**
 * Stores a newly placed Order Id locally so it appears in Order History.
 * Called once immediately after a successful checkout.
 * @param {string} orderId - Salesforce Order Id returned by CheckoutController.submitOrder
 */
export function rememberOrder(orderId) {
    const ids = readIds();
    if (!ids.includes(orderId)) {
        ids.unshift(orderId); // newest first
        writeIds(ids);
    }
}

/**
 * Remembers the email used at checkout so Order History can look up every
 * website order for this shopper by email (see getMyOrders), not just the
 * ones whose ids happen to still be in this browser's localStorage.
 * @param {string} email - the email entered on the shipping form
 */
export function rememberEmail(email) {
    if (!email) { return; }
    try {
        window.localStorage.setItem(EMAIL_STORAGE_KEY, email);
    } catch (e) {
        // storage unavailable — email-based lookup just won't be available
    }
}

/**
 * Reads the last remembered checkout email, if any.
 * @returns {string|null}
 */
function readEmail() {
    try {
        return window.localStorage.getItem(EMAIL_STORAGE_KEY);
    } catch (e) {
        return null;
    }
}

/**
 * Returns full order details for every website order placed by this shopper.
 * Prefers looking up by the last remembered checkout email (CheckoutController.
 * getOrdersByEmail), since that finds every order for this shopper regardless
 * of which browser/session placed it — then merges in any locally remembered
 * order ids not already covered (e.g. orders placed before email tracking
 * existed, or if local storage and the email happen to disagree).
 * @returns {Promise<Array>} resolves to an array of OrderSummary objects
 */
export function getMyOrders() {
    const email = readEmail();
    const ids = readIds();

    if (!email) {
        if (ids.length === 0) { return Promise.resolve([]); }
        return getOrders({ orderIds: ids });
    }

    return getOrdersByEmail({ email }).then((byEmail) => {
        const covered = new Set(byEmail.map((o) => o.orderId));
        const missingIds = ids.filter((id) => !covered.has(id));
        if (missingIds.length === 0) { return byEmail; }
        return getOrders({ orderIds: missingIds }).then((extra) => [...byEmail, ...extra]);
    });
}

/**
 * Cancels a website order (only Draft/Activated orders can be cancelled).
 * @param {string} orderId - Salesforce Order Id
 * @returns {Promise<void>}
 */
export function cancelOrder(orderId) {
    return cancelOrderApex({ orderId });
}

/**
 * Returns full order details for a single order by its Salesforce Id.
 * @param {string} orderId - Salesforce Order Id
 * @returns {Promise<Object|null>} resolves to an OrderSummary object or null if not found
 */
export function getOrder(orderId) {
    if (!orderId) { return Promise.resolve(null); }
    return getOrders({ orderIds: [orderId] }).then((results) => results[0] || null);
}
