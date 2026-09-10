import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getCheckoutRef } from 'c/navigationService';
import { calculateTotals } from 'c/cartCalculations';

/**
 * TechBasketOrderSummary — shared order totals panel.
 * Used on both the Cart page and the Checkout page's sidebar.
 * Shows subtotal, shipping, tax, and grand total.
 */
export default class TechBasketOrderSummary extends NavigationMixin(LightningElement) {
    /** Cart items array passed in from the parent. */
    @api items = [];
    /** Shipping cost in rupees passed in from the parent (0 = free). */
    @api shippingCost = 0;
    /** When true, hides the "Proceed to Checkout" button (used on the Checkout page itself). */
    @api hideCheckoutButton = false;

    /**
     * Returns the full totals object: subtotal, shipping, tax, total.
     * Calculated by cartCalculations using the current items and shipping cost.
     */
    get totals() {
        return calculateTotals(this.items, { shippingCost: this.shippingCost });
    }

    /** Navigates to the Checkout page. */
    handleCheckout() {
        this[NavigationMixin.Navigate](getCheckoutRef());
    }
}
