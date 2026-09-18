import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getProductRef } from 'c/navigationService';
import { getProductImages } from 'c/brandService';
import { toggleWishlist, isWishlisted } from 'c/wishlistService';
import { showToast } from 'c/toastService';
import { loadProducts, findById } from 'c/productDataService';

/**
 * TechBasketCartItem — a single row in the Shopping Cart.
 * Displays the product image (from brandService/tbimages static resource),
 * name, unit price, quantity selector, subtotal, and a remove button.
 * Bubbles quantitychange and remove events up to techBasketCart.
 */
export default class TechBasketCartItem extends NavigationMixin(LightningElement) {
    /** Cart item object: { productId, productName, price, quantity }. */
    @api item;
    /** True when the product image fails to load — hides the img element. */
    @track imgError = false;
    /** Real tracked stock ceiling for this line's product — null (untracked) falls back to the quantity selector's own default. */
    @track maxQuantity = 99;

    /**
     * Lifecycle: looks up this line's real current stock so the +/-
     * stepper can't be pushed past what's actually available — cart items
     * only ever carry {productId, productName, price, quantity}, not stock,
     * so this is the one place in the cart that needs the full catalog.
     */
    connectedCallback() {
        loadProducts().then((products) => {
            const product = findById(products, this.item.productId);
            if (product && product.stockQuantity != null) {
                this.maxQuantity = product.stockQuantity;
            }
        });
    }

    /**
     * Returns the first product image URL from brandService.
     * Returns an empty string if the image previously failed to load,
     * which triggers the letter-placeholder fallback in the template.
     */
    get productImage() {
        if (this.imgError) return '';
        const images = getProductImages(this.item && this.item.productName);
        return images && images[0] ? images[0] : '';
    }

    /**
     * Returns the line subtotal (price × quantity) formatted in Indian locale.
     * Example: "1,20,000" for ₹1,20,000.
     */
    get subtotal() {
        return (this.item.price * this.item.quantity).toLocaleString('en-IN');
    }

    /**
     * Sets the imgError flag when the product image fails to load,
     * causing the template to fall back to the letter placeholder.
     */
    handleImgError() {
        this.imgError = true;
    }

    /** Navigates to the Product Detail page for this cart item's product. */
    handleViewProduct() {
        this[NavigationMixin.Navigate](getProductRef(this.item.productId));
    }

    /**
     * Bubbles a quantitychange event to the parent techBasketCart
     * when the quantity selector fires a change event.
     * @param {CustomEvent} event - detail.quantity from techBasketQuantitySelector
     */
    handleQuantityChange(event) {
        this.dispatchEvent(new CustomEvent('quantitychange', {
            detail: { productId: this.item.productId, quantity: event.detail.quantity }
        }));
    }

    /**
     * Bubbles a remove event to the parent techBasketCart
     * when the remove button is clicked.
     */
    handleRemove() {
        this.dispatchEvent(new CustomEvent('remove', { detail: { productId: this.item.productId } }));
    }

    /**
     * Moves this line to the wishlist: adds it there (unless already saved)
     * and removes it from the cart via the same 'remove' event the Remove
     * button uses, so techBasketCart's existing cart-mutation handling
     * doesn't need a second code path.
     */
    handleSaveForLater() {
        if (!isWishlisted(this.item.productId)) {
            toggleWishlist(this.item.productId);
        }
        showToast(`${this.item.productName} saved for later — moved to your wishlist.`, 'success');
        this.dispatchEvent(new CustomEvent('saveforlater', { detail: { productId: this.item.productId } }));
    }
}
