import { getSession, subscribe as subscribeToAuth } from 'c/authService';
import updateCartSnapshot from '@salesforce/apex/LoginCredentialsController.updateCartSnapshot';
import logCartActivity from '@salesforce/apex/LoginCredentialsController.logCartActivity';

/** localStorage key used to persist the cart across page navigations. */
const STORAGE_KEY = 'techbasket_cart';
/** Set of subscriber callbacks notified on every cart mutation. */
const listeners = new Set();

/**
 * Mirrors the cart onto the logged-in shopper's Login_Credentials__c record
 * (Cart_Items__c) so an admin can see their live cart on the account
 * record. A no-op for guests (nobody's account to mirror onto yet) — cart
 * stays local-only exactly as before until they log in. Fire-and-forget:
 * failures are swallowed so a sync hiccup never blocks actual shopping.
 * @param {Array} items - current cart items array
 */
function syncCartToAccount(items) {
    const session = getSession();
    if (!session || !session.id) {
        return;
    }
    const cartSummary = items.length === 0
        ? '(cart is empty)'
        : items
            .map((i) => `${i.productName} — Qty ${i.quantity} (₹${i.price} each)`)
            .join('\n') +
          `\n\nCart Total: ₹${items.reduce((sum, i) => sum + i.price * i.quantity, 0)}`;

    updateCartSnapshot({ loginCredentialsId: session.id, cartSummary })
        .catch(() => { /* best-effort mirror only */ });
}

/**
 * Records one row of permanent cart history (Cart_Activity__c) for a single
 * add/remove/clear action. A no-op for guests, same as syncCartToAccount —
 * only logged-in shoppers have an account record to attach history to.
 * @param {string} action - 'Added' | 'Removed' | 'Cart Cleared'
 * @param {string} productName
 * @param {number} quantity - how many units this specific action involved
 * @param {number} price - price per unit, or null if not applicable
 */
function logActivity(action, productName, quantity, price) {
    const session = getSession();
    if (!session || !session.id) {
        return;
    }
    logCartActivity({
        loginCredentialsId: session.id,
        action,
        productName,
        quantity,
        price: price == null ? null : price
    }).catch(() => { /* best-effort history only */ });
}

// Syncs the current cart the moment a shopper logs in, so items added
// while browsing as a guest (before Cart_Items__c had anywhere to mirror
// to) show up on their account immediately, not just after their next
// add/remove.
subscribeToAuth((session) => {
    if (session) {
        syncCartToAccount(readCart());
    }
});

/**
 * Reads the cart from localStorage.
 * Returns an empty array if storage is unavailable or the data is corrupt.
 * @returns {Array} array of cart item objects
 */
function readCart() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

/**
 * Persists the cart to localStorage and notifies all subscribers.
 * Silently skips the write if storage is unavailable (state stays in-memory).
 * @param {Array} items - updated cart items array
 */
function writeCart(items) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(items));
    } catch (e) {
        // storage unavailable — state stays in-memory for this session
    }
    listeners.forEach((cb) => cb(items));
    syncCartToAccount(items);
}

/**
 * Returns the current cart items array.
 * @returns {Array} array of cart item objects
 */
export function getCart() {
    return readCart();
}

/**
 * Returns the total number of units across all cart items.
 * Used by the header badge.
 * @returns {number} total item count
 */
export function getCartCount() {
    return readCart().reduce((sum, item) => sum + item.quantity, 0);
}

/**
 * Returns the quantity of a specific product currently in the cart.
 * Returns 0 if the product is not in the cart.
 * Used by product cards to switch between "Add to Cart" and the +/- stepper.
 * @param {string} productId - Salesforce Product2 Id
 * @returns {number} quantity in cart (0 if not present)
 */
export function getItemQuantity(productId) {
    const item = readCart().find((i) => i.productId === productId);
    return item ? item.quantity : 0;
}

/**
 * Adds a quantity of a product to the cart.
 * If the product is already in the cart, increments its quantity.
 * @param {Object} product - must have productId, productName, price
 * @param {number} quantity - number of units to add
 * @returns {Array} updated cart items array
 */
export function addItem(product, quantity) {
    const items = readCart();
    const existing = items.find((i) => i.productId === product.productId);
    if (existing) {
        existing.quantity += quantity;
    } else {
        items.push({ productId: product.productId, productName: product.productName, price: product.price, quantity });
    }
    writeCart(items);
    logActivity('Added', product.productName, quantity, product.price);
    return items;
}

/**
 * Sets the quantity of a specific cart item to an exact value.
 * @param {string} productId - Salesforce Product2 Id
 * @param {number} quantity - new quantity value
 * @returns {Array} updated cart items array
 */
export function updateQuantity(productId, quantity) {
    const items = readCart();
    const item = items.find((i) => i.productId === productId);
    if (item) {
        const delta = quantity - item.quantity;
        item.quantity = quantity;
        writeCart(items);
        if (delta > 0) {
            logActivity('Added', item.productName, delta, item.price);
        } else if (delta < 0) {
            logActivity('Removed', item.productName, Math.abs(delta), item.price);
        }
    } else {
        writeCart(items);
    }
    return items;
}

/**
 * Removes a product from the cart entirely.
 * @param {string} productId - Salesforce Product2 Id
 * @returns {Array} updated cart items array
 */
export function removeItem(productId) {
    const all = readCart();
    const removed = all.find((i) => i.productId === productId);
    const items = all.filter((i) => i.productId !== productId);
    writeCart(items);
    if (removed) {
        logActivity('Removed', removed.productName, removed.quantity, removed.price);
    }
    return items;
}

/**
 * Removes all items from the cart.
 * @returns {Array} empty array
 */
export function clearCart() {
    const items = readCart();
    writeCart([]);
    if (items.length > 0) {
        const totalUnits = items.reduce((sum, i) => sum + i.quantity, 0);
        logActivity('Cart Cleared', `${items.length} product(s), ${totalUnits} unit(s)`, totalUnits, null);
    }
    return [];
}

/**
 * Subscribes a callback to cart change events.
 * The callback is called with the updated items array after every mutation.
 * @param {Function} callback - called with (items) on every cart change
 * @returns {Function} unsubscribe function — call it in disconnectedCallback
 */
export function subscribe(callback) {
    listeners.add(callback);
    return () => listeners.delete(callback);
}
