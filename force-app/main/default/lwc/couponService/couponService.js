/**
 * couponService — carries a coupon code a shopper applied on the Cart page
 * forward to the Payment page, so they don't have to retype it. Both pages
 * independently re-validate the code for real via
 * CheckoutController.previewOrderTotals (this module only stores the raw
 * string — it is never treated as a validated discount).
 */
const STORAGE_KEY = 'techbasket_applied_coupon';

/**
 * Returns the last coupon code applied, or null if none / storage unavailable.
 * @returns {string|null}
 */
export function getAppliedCoupon() {
    try {
        return window.localStorage.getItem(STORAGE_KEY) || null;
    } catch (e) {
        return null;
    }
}

/**
 * Stores the applied coupon code, or clears it when passed a falsy value.
 * @param {string|null} code
 */
export function setAppliedCoupon(code) {
    try {
        if (code) {
            window.localStorage.setItem(STORAGE_KEY, code);
        } else {
            window.localStorage.removeItem(STORAGE_KEY);
        }
    } catch (e) {
        // storage unavailable — the coupon simply won't carry over between pages
    }
}
