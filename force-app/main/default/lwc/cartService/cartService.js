/** localStorage key used to persist the cart across page navigations. */
const STORAGE_KEY = 'techbasket_cart';
/** Set of subscriber callbacks notified on every cart mutation. */
const listeners = new Set();

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
    if (item) { item.quantity = quantity; }
    writeCart(items);
    return items;
}

/**
 * Removes a product from the cart entirely.
 * @param {string} productId - Salesforce Product2 Id
 * @returns {Array} updated cart items array
 */
export function removeItem(productId) {
    const items = readCart().filter((i) => i.productId !== productId);
    writeCart(items);
    return items;
}

/**
 * Removes all items from the cart.
 * @returns {Array} empty array
 */
export function clearCart() {
    writeCart([]);
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
