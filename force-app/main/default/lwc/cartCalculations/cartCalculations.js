/**
 * Frontend estimate tax rate — mirrors OrderPricingService.DEFAULT_GST_RATE_PERCENT
 * (18%, the standard GST slab for laptops/computers, HSN 8471), which every
 * real product in this catalog falls back to (none currently override
 * Product2.GST_Rate__c). This is still only an ESTIMATE shown before the
 * real server pricing engine runs (Cart/Checkout, ahead of Payment) — the
 * actual charge always comes from OrderPricingService.calculate, which
 * computes GST per line at that product's own real rate. Keep this in sync
 * with DEFAULT_GST_RATE_PERCENT if that default ever changes.
 */
const TAX_RATE = 0.18;

/**
 * cartCalculations — pure functions for order total arithmetic.
 * Used by both techBasketOrderSummary (cart page) and techBasketPayment (payment page)
 * so totals are always calculated the same way.
 */

/**
 * Calculates the order subtotal by summing price × quantity for each cart item.
 * @param {Array} items - array of cart item objects with price and quantity fields
 * @returns {number} subtotal in rupees
 */
export function calculateSubtotal(items) {
    return items.reduce((sum, item) => sum + item.price * item.quantity, 0);
}

/**
 * Applies the frontend tax rate to a subtotal.
 * Result is rounded to the nearest rupee.
 * @param {number} subtotal - order subtotal in rupees
 * @returns {number} tax amount in rupees
 */
export function calculateTax(subtotal) {
    return Math.round(subtotal * TAX_RATE);
}

/**
 * Calculates all order totals in one call.
 * Returns subtotal, shipping, tax, discount, and grand total.
 * Grand total is clamped to 0 to prevent negative values from large discounts.
 * @param {Array} items - array of cart item objects
 * @param {Object} [options]
 * @param {number} [options.shippingCost=0] - shipping cost in rupees
 * @param {number} [options.discountAmount=0] - discount amount in rupees
 * @returns {{ subtotal: number, shipping: number, tax: number, discount: number, total: number }}
 */
export function calculateTotals(items, { shippingCost = 0, discountAmount = 0 } = {}) {
    const subtotal = calculateSubtotal(items);
    const tax      = calculateTax(subtotal);
    const total    = Math.max(0, subtotal + shippingCost + tax - discountAmount);
    return { subtotal, shipping: shippingCost, tax, discount: discountAmount, total };
}
