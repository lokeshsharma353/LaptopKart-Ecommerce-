import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getShopRef } from 'c/navigationService';
import { getCart, updateQuantity, removeItem, clearCart, subscribe } from 'c/cartService';
import { showToast } from 'c/toastService';

/**
 * TechBasketCart — the Shopping Cart page.
 * Renders the list of cart items via techBasketCartItem, order totals via
 * techBasketOrderSummary, and a confirmation modal for the "Clear Cart" action.
 */
export default class TechBasketCart extends NavigationMixin(LightningElement) {
    /** Current cart items array — kept in sync with cartService via subscription. */
    @track items = [];
    /** Controls visibility of the "Clear Cart" confirmation modal. */
    @track showClearConfirm = false;

    /** Unsubscribe function from cartService — called on disconnect. */
    unsubscribeCart;

    /**
     * Lifecycle: loads the current cart and subscribes to future changes
     * so the item list and totals update in real time.
     */
    connectedCallback() {
        this.items = getCart();
        this.unsubscribeCart = subscribe((items) => {
            this.items = items;
        });
    }

    /**
     * Lifecycle: cleans up the cart subscription to prevent memory leaks.
     */
    disconnectedCallback() {
        if (this.unsubscribeCart) {
            this.unsubscribeCart();
        }
    }

    /** True when the cart has at least one item. */
    get hasItems() {
        return this.items.length > 0;
    }

    /** Human-readable item count label shown in the cart header (e.g. "3 items"). */
    get itemCountLabel() {
        const count = this.items.reduce((sum, i) => sum + i.quantity, 0);
        return `${count} item${count === 1 ? '' : 's'}`;
    }

    /**
     * Handles a quantity change event bubbled up from a techBasketCartItem.
     * Updates the shared cart; the subscription above refreshes this component and the header badge.
     * @param {CustomEvent} event - detail.productId and detail.quantity
     */
    handleQuantityChange(event) {
        updateQuantity(event.detail.productId, event.detail.quantity);
    }

    /**
     * Handles a remove event bubbled up from a techBasketCartItem.
     * Removes the item from the cart and shows a success toast.
     * @param {CustomEvent} event - detail.productId
     */
    handleRemove(event) {
        removeItem(event.detail.productId);
        showToast('Product removed from cart.', 'success');
    }

    /** Navigates back to the Product Catalog page. */
    handleContinueShopping() {
        this[NavigationMixin.Navigate](getShopRef());
    }

    /** Shows the "Clear Cart" confirmation modal. */
    handleClearCartClick() {
        this.showClearConfirm = true;
    }

    /** Hides the "Clear Cart" confirmation modal without clearing the cart. */
    handleCancelClear() {
        this.showClearConfirm = false;
    }

    /**
     * Clears all items from the cart, hides the confirmation modal,
     * and shows a success toast.
     */
    handleConfirmClear() {
        clearCart();
        this.showClearConfirm = false;
        showToast('Cart cleared.', 'success');
    }
}
