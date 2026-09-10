/**
 * addressService — localStorage-backed saved address book.
 * Until real customer login is wired up, "saved addresses" are scoped to
 * this browser, the same way cartService/wishlistService work. Used by the
 * "Save this address" checkbox on the Shipping step and by the Saved
 * Addresses section of My Account, so an address saved during checkout
 * actually shows up there (and vice versa) instead of being two disconnected
 * fake lists.
 */
const STORAGE_KEY = 'techbasket_saved_addresses';

/**
 * Reads the saved address array from localStorage.
 * Returns an empty array if storage is unavailable or the data is corrupt.
 * @returns {Array} array of address objects, newest first
 */
function readAddresses() {
    try {
        const raw = window.localStorage.getItem(STORAGE_KEY);
        return raw ? JSON.parse(raw) : [];
    } catch (e) {
        return [];
    }
}

/**
 * Persists the address array to localStorage.
 * Silently skips the write if storage is unavailable.
 * @param {Array} addresses - array of address objects
 */
function writeAddresses(addresses) {
    try {
        window.localStorage.setItem(STORAGE_KEY, JSON.stringify(addresses));
    } catch (e) {
        // storage unavailable — the address just won't persist across reloads
    }
}

/**
 * Returns every saved address.
 * @returns {Array} array of address objects
 */
export function getAddresses() {
    return readAddresses();
}

/**
 * Saves a new address, or updates an existing one if `address.id` matches
 * a saved address. Fields beyond line1/city/phone (address2/state/postalCode/
 * country) are preserved even though My Account's simple edit form only
 * exposes line1/city/phone, so an address saved from the full Shipping form
 * doesn't lose its state/postal/country when later edited from My Account.
 * @param {Object} address - address fields; an existing `id` updates in place
 * @returns {Object} the saved address record, including its id
 */
export function saveAddress(address) {
    const addresses = readAddresses();
    const id = address.id || `addr_${Date.now()}`;
    const record = { ...address, id };
    const existingIndex = addresses.findIndex((a) => a.id === id);

    if (existingIndex >= 0) {
        addresses[existingIndex] = { ...addresses[existingIndex], ...record };
    } else {
        addresses.unshift(record);
    }

    writeAddresses(addresses);
    return record;
}

/**
 * Removes a saved address by id.
 * @param {string} id - address id to remove
 */
export function deleteAddress(id) {
    writeAddresses(readAddresses().filter((a) => a.id !== id));
}
