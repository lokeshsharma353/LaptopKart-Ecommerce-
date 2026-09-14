import { LightningElement, track, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { loadProducts, findById, filterByCategory } from 'c/productDataService';
import { addItem, getItemQuantity, updateQuantity } from 'c/cartService';
import { showToast } from 'c/toastService';
import { isWishlisted, toggleWishlist } from 'c/wishlistService';
import { getBrandForProduct, getProductImages } from 'c/brandService';
import { getCheckoutRef, getAccountRef } from 'c/navigationService';
import { isLoggedIn } from 'c/authService';

/** Mock reviews — a real Salesforce review object is not in scope for this project. */
const MOCK_REVIEWS = [
    { id: 'r1', name: 'Aditi R.', rating: 5, comment: 'Exceeded expectations, arrived a day early too.' },
    { id: 'r2', name: 'Karan V.', rating: 4, comment: 'Solid build quality for the price point.' }
];

/** Mock FAQs — real FAQ content would come from a Salesforce Knowledge article. */
const MOCK_FAQS = [
    { id: 'f1', question: 'What is the warranty period?', answer: '1-year manufacturer warranty is included.' },
    { id: 'f2', question: 'Is international shipping available?', answer: 'Currently we ship within the country only.' }
];

/**
 * TechBasketProductDetail — Apple-style product detail page.
 * Features: sticky image gallery with thumbnail strip, info panel with quantity selector,
 * wishlist toggle, social share, description/reviews/FAQs tabs, and related products.
 * Product data comes from ProductCatalogController (real Product2/PricebookEntry).
 */
export default class TechBasketProductDetail extends NavigationMixin(LightningElement) {
    /** Salesforce Id of the product currently being viewed. */
    @track productId;
    /** Quantity to add to cart — controlled by the quantity selector component. */
    @track quantity = 1;
    /** Index of the image currently shown in the main gallery. */
    @track activeImageIndex = 0;
    /** True when the description text is fully expanded (not clamped). */
    @track descriptionExpanded = false;
    /** Active tab key: 'description' | 'reviews' | 'faqs'. */
    @track activeTab = 'description';
    /** True when this product is in the user's wishlist. */
    @track wishlisted = false;
    /** True while the Apex product call is in flight. */
    @track isLoading = true;
    /** True for 2.2 seconds after "Add to Cart" is clicked — shows "✓ Added to Cart!". */
    @track justAdded = false;
    /** setTimeout reference for resetting the justAdded state. */
    _addedTimer;

    /** Full product list — needed to find the current product and related products. */
    allProducts = [];
    /** Mock reviews enriched with a stars array for the star rating display. */
    mockReviews = MOCK_REVIEWS.map(r => ({ ...r, stars: Array.from({ length: r.rating }, (_, i) => i) }));
    mockFaqs = MOCK_FAQS;

    /**
     * Lifecycle: loads the full product catalog from Apex.
     * The current product is derived from allProducts using the productId from navigation state.
     */
    connectedCallback() {
        loadProducts()
            .then((products) => {
                this.allProducts = products;
                this.isLoading = false;
            })
            .catch(() => {
                this.isLoading = false;
            });
    }

    /**
     * Wire: reads the productId from navigation state (set by catalog/search/card navigation).
     * Resets gallery, quantity, and tab state whenever a new product is navigated to.
     * @param {Object} pageRef - LWR page reference object
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const id = pageRef && pageRef.state && pageRef.state.productId;
        if (id && id !== this.productId) {
            this.productId = id;
            this.quantity = 1;
            this.activeImageIndex = 0;
            this.descriptionExpanded = false;
            this.activeTab = 'description';
            this.wishlisted = isWishlisted(id);
        }
    }

    /** Returns the current product object, or null if not yet loaded. */
    get product() {
        return this.productId ? findById(this.allProducts, this.productId) : null;
    }

    /** First letter of the product name — shown as a placeholder when no image is available. */
    get categoryInitial() {
        return this.product ? this.product.productName.charAt(0).toUpperCase() : '?';
    }

    /** Full list of product image URLs from brandService (served from tbimages static resource). */
    get productImages() {
        return getProductImages(this.product && this.product.productName);
    }

    /** URL of the currently active image in the gallery. */
    get activeImageUrl() {
        return this.productImages[this.activeImageIndex] || this.productImages[0];
    }

    /** Brand name derived from the product name (e.g. "Apple", "Dell"). */
    get brandName() {
        return getBrandForProduct(this.product && this.product.productName).name;
    }

    /** Add to Cart button label — shows "✓ Added to Cart!" briefly after clicking. */
    get addCartLabel() { return this.justAdded ? '✓ Added to Cart!' : 'Add to Cart'; }
    /** Add to Cart button CSS class — adds a success modifier when justAdded. */
    get addCartClass() { return this.justAdded ? 'tb-add-cart-btn tb-added' : 'tb-add-cart-btn'; }

    /** Price formatted in Indian locale (e.g. "1,20,000"). */
    get formattedPrice() {
        return this.product ? Number(this.product.price).toLocaleString('en-IN') : '';
    }

    /** Wishlist button label — changes based on current wishlist state. */
    get wishlistLabel() {
        return this.wishlisted ? 'Wishlisted' : 'Add to Wishlist';
    }

    /**
     * Builds the thumbnail strip array for the gallery.
     * Each thumbnail carries its URL, index, and active CSS class.
     */
    get thumbnails() {
        return this.productImages.map((url, i) => ({
            index: i,
            url,
            className: i === this.activeImageIndex ? 'tb-thumbnail tb-thumbnail-active' : 'tb-thumbnail',
            dotClass: i === this.activeImageIndex ? 'tb-dot-active' : ''
        }));
    }

    /** CSS class for the description text — clamped to a few lines unless expanded. */
    get descriptionClass() {
        return this.descriptionExpanded ? 'tb-description-text' : 'tb-description-text tb-description-clamped';
    }

    /** Label for the description expand/collapse toggle button. */
    get descriptionToggleLabel() {
        return this.descriptionExpanded ? 'Read Less' : 'Read More';
    }

    /** CSS class for the wishlist button — adds an active modifier when wishlisted. */
    get wishlistClass() {
        return this.wishlisted ? 'tb-wishlist-btn tb-wishlist-active' : 'tb-wishlist-btn';
    }

    /** Heart icon character — filled (♥) when wishlisted, outline (♡) otherwise. */
    get wishlistIcon() {
        return this.wishlisted ? '♥' : '♡';
    }

    /**
     * Builds the tab button array for Description / Reviews / FAQs.
     * The active tab gets a distinct CSS class.
     */
    get tabs() {
        const names = ['description', 'reviews', 'faqs'];
        const labels = { description: 'Description', reviews: 'Reviews', faqs: 'FAQs' };
        return names.map((name) => ({
            name,
            label: labels[name],
            className: name === this.activeTab ? 'tb-tab-btn tb-tab-btn-active' : 'tb-tab-btn'
        }));
    }

    /** True when the Description tab is active. */
    get isDescriptionTab() { return this.activeTab === 'description'; }
    /** True when the Reviews tab is active. */
    get isReviewsTab()     { return this.activeTab === 'reviews'; }
    /** True when the FAQs tab is active. */
    get isFaqsTab()        { return this.activeTab === 'faqs'; }

    /**
     * Returns up to 4 other products from the same category for the "Related Products" strip.
     * Excludes the current product from the list.
     */
    get relatedProducts() {
        if (!this.product) { return []; }
        return filterByCategory(this.allProducts, this.product.category)
            .filter((p) => p.productId !== this.product.productId)
            .slice(0, 4);
    }

    /** Facebook share URL for the current page. */
    get facebookShareUrl() {
        return `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(window.location.href)}`;
    }

    /** Twitter share URL for the current page. */
    get twitterShareUrl() {
        return `https://twitter.com/intent/tweet?url=${encodeURIComponent(window.location.href)}`;
    }

    /** LinkedIn share URL for the current page. */
    get linkedInShareUrl() {
        return `https://www.linkedin.com/sharing/share-offsite/?url=${encodeURIComponent(window.location.href)}`;
    }

    /** Shows the previous image in the gallery (wraps around). */
    handlePrevImage() {
        this.activeImageIndex = (this.activeImageIndex - 1 + this.productImages.length) % this.productImages.length;
    }

    /** Shows the next image in the gallery (wraps around). */
    handleNextImage() {
        this.activeImageIndex = (this.activeImageIndex + 1) % this.productImages.length;
    }

    /**
     * Jumps to a specific image when a thumbnail is clicked.
     * @param {Event} event - currentTarget.dataset.index contains the target image index
     */
    handleThumbnailClick(event) {
        this.activeImageIndex = Number(event.currentTarget.dataset.index);
    }

    /** Toggles the description text between clamped and fully expanded. */
    toggleDescription() {
        this.descriptionExpanded = !this.descriptionExpanded;
    }

    /**
     * Updates the quantity when the quantity selector fires a change event.
     * @param {CustomEvent} event - detail.quantity contains the new quantity
     */
    handleQuantityChange(event) {
        this.quantity = event.detail.quantity;
    }

    /**
     * Adds the selected quantity of this product to the cart, shows a success toast,
     * and briefly switches the button label to "✓ Added to Cart!" for 2.2 seconds.
     */
    handleAddToCart() {
        addItem(this.product, this.quantity);
        showToast(`${this.product.productName} added to cart!`, 'success');
        this.justAdded = true;
        if (this._addedTimer) clearTimeout(this._addedTimer);
        this._addedTimer = setTimeout(() => { this.justAdded = false; }, 2200);
    }

    /**
     * Buys this product right now at the currently selected quantity. Checks
     * login FIRST — if nobody's logged in, bounces to the Account page
     * without touching the cart at all, so a guest clicking "Buy Now" while
     * browsing never silently ends up with products in their cart they don't
     * remember adding. Only once logged in does it sync the cart to exactly
     * `this.quantity` rather than always adding on top of it — so if the
     * product is already in the cart (e.g. added earlier, or the shopper
     * bumped the quantity selector up before clicking) Buy Now reflects that
     * exact quantity instead of double-counting or silently resetting it
     * back to 1 — then jumps straight to Checkout.
     */
    handleBuyNow() {
        if (!isLoggedIn()) {
            showToast('Please log in to continue.', 'info');
            this[NavigationMixin.Navigate](getAccountRef());
            return;
        }
        const existingQuantity = getItemQuantity(this.product.productId);
        if (existingQuantity === 0) {
            addItem(this.product, this.quantity);
        } else if (existingQuantity !== this.quantity) {
            updateQuantity(this.product.productId, this.quantity);
        }
        this[NavigationMixin.Navigate](getCheckoutRef());
    }

    /**
     * Toggles this product in/out of the wishlist and shows a toast confirming the action.
     */
    handleToggleWishlist() {
        this.wishlisted = toggleWishlist(this.product.productId);
        showToast(
            this.wishlisted ? 'Added to wishlist!' : 'Removed from wishlist.',
            this.wishlisted ? 'success' : 'info'
        );
    }

    /**
     * Switches the active tab when a tab button is clicked.
     * @param {Event} event - currentTarget.dataset.tab contains the tab key
     */
    handleTabClick(event) {
        this.activeTab = event.currentTarget.dataset.tab;
    }

    /**
     * Copies the current page URL to the clipboard using the Clipboard API.
     * Shows a success toast on completion.
     */
    handleCopyLink() {
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(window.location.href).then(() => {
                showToast('Link copied.', 'success');
            });
        }
    }
}
