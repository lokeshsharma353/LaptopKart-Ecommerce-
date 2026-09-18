import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getCartRef, getCheckoutRef, getProductRef } from 'c/navigationService';
import { getCart, updateQuantity, removeItem, subscribe } from 'c/cartService';
import { isLoggedIn } from 'c/authService';
import { getAccountRef } from 'c/navigationService';
import { showToast } from 'c/toastService';
import { loadProducts, findById } from 'c/productDataService';

/**
 * TechBasketMiniCart — slide-in drawer opened from the header cart icon.
 * Lets a shopper review/adjust quantities and jump straight to Checkout
 * without a full page navigation to the Cart page for a quick glance.
 */
export default class TechBasketMiniCart extends NavigationMixin(LightningElement) {
    /** Current cart items array. */
    @track items = [];
    /** Full product catalog — used only to enforce each line's real stock ceiling on the +/- stepper. */
    allProducts = [];

    /** Unsubscribe function from cartService — called on disconnect. */
    unsubscribeCart;

    /** Bound reference to handleKeydown — needed to remove the exact same listener on disconnect. */
    _boundKeydown;

    connectedCallback() {
        this.items = getCart();
        this.unsubscribeCart = subscribe((items) => {
            this.items = items;
        });
        loadProducts().then((products) => { this.allProducts = products; });
        // Prevent the page behind the drawer from scrolling while it's open.
        document.body.style.overflow = 'hidden';

        this._boundKeydown = this.handleKeydown.bind(this);
        window.addEventListener('keydown', this._boundKeydown);
    }

    disconnectedCallback() {
        if (this.unsubscribeCart) { this.unsubscribeCart(); }
        document.body.style.overflow = '';
        window.removeEventListener('keydown', this._boundKeydown);
    }

    /** Closes the drawer when the shopper presses Escape, the standard way to dismiss a slide-in panel. */
    handleKeydown(event) {
        if (event.key === 'Escape') {
            this.handleClose();
        }
    }

    /** Cart items enriched with a computed line total for display. */
    get lineItems() {
        return this.items.map((i) => ({ ...i, lineTotal: i.price * i.quantity }));
    }

    /** True when the cart has at least one item. */
    get hasItems() { return this.items.length > 0; }

    /** Sum of every line total in the cart. */
    get subtotal() {
        return this.items.reduce((sum, i) => sum + i.price * i.quantity, 0);
    }

    /** Total unit count across all cart items, shown in the drawer header. */
    get itemCount() {
        return this.items.reduce((sum, i) => sum + i.quantity, 0);
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
    }

    handleIncrease(event) {
        const productId = event.currentTarget.dataset.id;
        const item = this.items.find((i) => i.productId === productId);
        if (!item) { return; }
        const product = findById(this.allProducts, productId);
        if (product && product.stockQuantity != null && item.quantity >= product.stockQuantity) {
            showToast(`Only ${product.stockQuantity} in stock.`, 'error');
            return;
        }
        updateQuantity(productId, item.quantity + 1);
    }

    handleDecrease(event) {
        const productId = event.currentTarget.dataset.id;
        const item = this.items.find((i) => i.productId === productId);
        if (!item) { return; }
        if (item.quantity <= 1) {
            removeItem(productId);
        } else {
            updateQuantity(productId, item.quantity - 1);
        }
    }

    handleRemove(event) {
        removeItem(event.currentTarget.dataset.id);
    }

    handleProductClick(event) {
        this.handleClose();
        this[NavigationMixin.Navigate](getProductRef(event.currentTarget.dataset.id));
    }

    handleViewCart() {
        this.handleClose();
        this[NavigationMixin.Navigate](getCartRef());
    }

    /** Jumps to Checkout, same login gate the product card/detail Buy Now buttons use. */
    handleCheckout() {
        if (!isLoggedIn()) {
            showToast('Please log in to continue.', 'info');
            this.handleClose();
            this[NavigationMixin.Navigate](getAccountRef());
            return;
        }
        this.handleClose();
        this[NavigationMixin.Navigate](getCheckoutRef());
    }
}
