import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getProductRef } from 'c/navigationService';
import { getProductImages } from 'c/brandService';

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
}
