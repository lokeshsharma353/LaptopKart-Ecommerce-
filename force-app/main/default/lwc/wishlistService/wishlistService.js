/** localStorage key used to persist the wishlist across page navigations. */
const STORAGE_KEY = 'techbasket_wishlist';

/**
 * Reads the wishlist (array of productIds) from localStorage.
 * Returns an empty array if storage is unavailable or the data is corrupt.
 * @returns {string[]} array of wishlisted Salesforce Product2 Ids
 */
function readWishlist() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

/**
 * Persists the wishlist array to localStorage.
 * Silently skips the write if storage is unavailable.
 * @param {string[]} ids - array of Salesforce Product2 Ids
 */
function writeWishlist(ids) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(ids));
    } catch (e) {
        // storage unavailable — state stays in-memory for this session
    }
}

/**
 * Returns the current wishlist as an array of product Ids.
 * @returns {string[]} array of wishlisted Salesforce Product2 Ids
 */
export function getWishlist() {
    return readWishlist();
}

/**
 * Returns true when the given product is in the wishlist.
 * @param {string} productId - Salesforce Product2 Id
 * @returns {boolean}
 */
export function isWishlisted(productId) {
    return readWishlist().includes(productId);
}

/**
 * Adds the product to the wishlist if it is not already there,
 * or removes it if it is. Returns the new wishlist state for the product.
 * @param {string} productId - Salesforce Product2 Id
 * @returns {boolean} true if the product is now wishlisted, false if removed
 */
export function toggleWishlist(productId) {
    const ids = readWishlist();
    const index = ids.indexOf(productId);
    if (index >= 0) {
        ids.splice(index, 1); // remove
    } else {
        ids.push(productId);  // add
    }
    writeWishlist(ids);
    return ids.includes(productId);
}
