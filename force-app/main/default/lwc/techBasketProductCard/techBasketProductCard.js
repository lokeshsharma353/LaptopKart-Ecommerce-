import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getProductRef, getCheckoutRef, getAccountRef } from 'c/navigationService';
import { addItem, updateQuantity, removeItem, getItemQuantity, subscribe } from 'c/cartService';
import { showToast } from 'c/toastService';
import { getProductImages, getBrandForProduct } from 'c/brandService';
import { isWishlisted, toggleWishlist } from 'c/wishlistService';
import { isLoggedIn } from 'c/authService';

/**
 * TechBasketProductCard — reusable product tile used in the catalog grid and homepage.
 * Features: image cycling on hover, wishlist heart toggle, "✓ Added!" cart feedback,
 * and a live +/- quantity stepper when the item is already in the cart.
 */
export default class TechBasketProductCard extends NavigationMixin(LightningElement) {
    /** Product object passed in from the parent (catalog, home, wishlist). */
    @api product;
    /** Current quantity of this product in the cart (0 = not in cart). */
    @track cartQuantity = 0;
    /** Index of the image currently shown in the card gallery. */
    @track activeImageIndex = 0;
    /** True while the mouse is over the card — triggers image cycling. */
    @track isHovered = false;
    /** True for 2 seconds after "Add to Cart" is clicked — shows "✓ Added!" label. */
    @track justAdded = false;
    /** True when this product is in the user's wishlist. */
    @track wishlisted = false;

    /** Unsubscribe function from cartService — called on disconnect. */
    unsubscribeCart;
    /** setInterval reference for the hover image cycling — cleared on mouse leave. */
    _imageInterval;
    /** setTimeout reference for resetting the justAdded state after 2 seconds. */
    _addedTimer;

    /**
     * Lifecycle: reads the initial cart quantity and wishlist state,
     * then subscribes to cart changes to keep the quantity stepper in sync.
     */
    connectedCallback() {
        this.cartQuantity = getItemQuantity(this.product.productId);
        this.wishlisted = isWishlisted(this.product.productId);
        this.unsubscribeCart = subscribe(() => {
            this.cartQuantity = getItemQuantity(this.product.productId);
        });
    }

    /**
     * Lifecycle: cleans up the cart subscription, image cycling interval,
     * and the "Added!" reset timer to prevent memory leaks.
     */
    disconnectedCallback() {
        if (this.unsubscribeCart) this.unsubscribeCart();
        this._stopCycle();
        if (this._addedTimer) clearTimeout(this._addedTimer);
    }

    /**
     * Returns up to 3 product images from brandService based on the product name.
     * Images are served from the tbimages static resource (CSP-safe).
     */
    get images() {
        return getProductImages(this.product && this.product.productName).slice(0, 3);
    }

    /** Returns the URL of the currently active image in the cycling gallery. */
    get activeImage() { return this.images[this.activeImageIndex]; }

    /**
     * Builds the dot indicator array for the image gallery.
     * The active dot gets a distinct CSS class for styling.
     */
    get imageDots() {
        return this.images.map((_, i) => ({
            index: i,
            cls: i === this.activeImageIndex ? 'tb-img-dot tb-img-dot-active' : 'tb-img-dot'
        }));
    }

    /** Brand name (e.g. "Apple", "Dell") shown as a small eyebrow label above the product name. */
    get brandName() {
        return getBrandForProduct(this.product && this.product.productName).name;
    }

    /** True when this product has at least one unit in the cart. */
    get inCart() { return this.cartQuantity > 0; }

    /** Returns the card's CSS class, adding a hover modifier when the mouse is over it. */
    get cardClass() {
        return this.isHovered ? 'tb-product-card tb-product-card-hovered' : 'tb-product-card';
    }

    /** Label for the Add to Cart button — shows "✓ Added!" briefly after clicking. */
    get addToCartLabel() { return this.justAdded ? '✓ Added!' : 'Add to Cart'; }
    /** CSS class for the Add to Cart button — adds a success modifier when justAdded. */
    get addToCartClass() { return this.justAdded ? 'tb-add-to-cart tb-added' : 'tb-add-to-cart'; }

    /** Heart icon character — filled (♥) when wishlisted, outline (♡) otherwise. */
    get wishlistIcon() { return this.wishlisted ? '♥' : '♡'; }
    /** CSS class for the wishlist button — adds an active modifier when wishlisted. */
    get wishlistBtnClass() { return this.wishlisted ? 'tb-wishlist-heart tb-wishlist-heart-active' : 'tb-wishlist-heart'; }
    /** Tooltip text for the wishlist button. */
    get wishlistTitle() { return this.wishlisted ? 'Remove from Wishlist' : 'Add to Wishlist'; }

    /**
     * Starts the image cycling interval (every 1.2 s) when the mouse enters the card.
     * Stops any existing interval first to avoid duplicates.
     */
    _startCycle() {
        this._stopCycle();
        this._imageInterval = setInterval(() => {
            this.activeImageIndex = (this.activeImageIndex + 1) % this.images.length;
        }, 1200);
    }

    /**
     * Clears the image cycling interval and nulls the reference.
     */
    _stopCycle() {
        if (this._imageInterval) { clearInterval(this._imageInterval); this._imageInterval = null; }
    }

    /** Starts image cycling and marks the card as hovered for CSS effects. */
    handleMouseEnter() { this.isHovered = true; this._startCycle(); }
    /** Stops image cycling, resets to the first image, and removes the hover state. */
    handleMouseLeave() { this.isHovered = false; this._stopCycle(); this.activeImageIndex = 0; }

    /** Navigates to the Product Detail page for this product. */
    handleViewProduct() {
        this[NavigationMixin.Navigate](getProductRef(this.product.productId));
    }

    /**
     * Adds one unit of this product to the cart, shows a success toast,
     * and briefly switches the button label to "✓ Added!" for 2 seconds.
     */
    handleAddToCart() {
        addItem(this.product, 1);
        showToast(`${this.product.productName} added to cart!`, 'success');
        this.justAdded = true;
        if (this._addedTimer) clearTimeout(this._addedTimer);
        this._addedTimer = setTimeout(() => { this.justAdded = false; }, 2000);
    }

    /**
     * Toggles this product in/out of the wishlist and shows a toast confirming the action.
     */
    handleWishlist() {
        this.wishlisted = toggleWishlist(this.product.productId);
        showToast(
            this.wishlisted ? `${this.product.productName} added to wishlist!` : 'Removed from wishlist.',
            this.wishlisted ? 'success' : 'info'
        );
    }

    /**
     * Buys this product right now: ensures at least 1 unit is in the cart
     * (without touching the quantity if it's already there — the shopper may
     * have already bumped it up via the +/- stepper, and Buy Now must carry
     * that quantity through, not reset it), then jumps straight to Checkout —
     * or to the Account page to log in first if nobody's logged in yet. The
     * Checkout page itself also gates on this (the authoritative check, for
     * shoppers who reach it via the cart instead), so this is purely to skip
     * a wasted navigate-then-bounce for the common Buy Now path.
     */
    handleBuyNow() {
        if (this.cartQuantity === 0) {
            addItem(this.product, 1);
        }
        if (!isLoggedIn()) {
            showToast('Please log in to continue.', 'info');
            this[NavigationMixin.Navigate](getAccountRef());
            return;
        }
        this[NavigationMixin.Navigate](getCheckoutRef());
    }

    /** Increments the cart quantity by 1 (used by the in-cart stepper). */
    handleIncrease() { addItem(this.product, 1); }

    /**
     * Decrements the cart quantity by 1.
     * If quantity would reach 0, removes the item entirely and shows an info toast.
     */
    handleDecrease() {
        if (this.cartQuantity <= 1) {
            removeItem(this.product.productId);
            showToast('Item removed from cart.', 'info');
        } else {
            updateQuantity(this.product.productId, this.cartQuantity - 1);
        }
    }
}
