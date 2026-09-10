import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { CurrentPageReference } from 'lightning/navigation';
import { getProductRef } from 'c/navigationService';
import { loadProducts, extractCategories } from 'c/productDataService';
import { addItem, updateQuantity, removeItem, getItemQuantity, subscribe } from 'c/cartService';
import { showToast } from 'c/toastService';

/** Number of products shown per page in the catalog grid or list view. */
const PAGE_SIZE = 12;
/** Default empty state for all filter fields. */
const DEFAULT_FILTERS = { search: '', category: '', minPrice: '', maxPrice: '' };

/**
 * TechBasketProductCatalog — the main shop/browse page.
 * Features: filter panel (search, category, price range), sort dropdown,
 * grid/list view toggle, pagination, and a live cart quantity stepper in list view.
 * Data comes from ProductCatalogController via productDataService.
 */
export default class TechBasketProductCatalog extends NavigationMixin(LightningElement) {
    /** Full product list loaded from Apex — never mutated directly. */
    @track allProducts = [];
    /** True while the Apex call is in flight. */
    @track isLoading = true;

    /** Filter values as the user edits them — not yet applied to results. */
    @track draftFilters = { ...DEFAULT_FILTERS };
    /** Filter values committed by "Apply Filters" — drives filteredProducts. */
    @track appliedFilters = { ...DEFAULT_FILTERS };

    /** Current sort key: 'newest' | 'priceLow' | 'priceHigh'. */
    @track sortBy = 'newest';
    /** Current view mode: 'grid' | 'list'. */
    @track viewMode = 'grid';
    /** Current page number (1-based). */
    @track currentPage = 1;

    /** Unsubscribe function from cartService — called on disconnect. */
    unsubscribeCart;

    /**
     * Lifecycle: loads the full product catalog from Apex and subscribes to cart
     * changes so list-view quantity steppers stay in sync with the cart badge.
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

        this.unsubscribeCart = subscribe(() => {
            // Shallow-copy forces pagedProducts (which reads live cart quantities) to recompute.
            this.allProducts = [...this.allProducts];
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

    /**
     * Wire: reads navigation state set by the homepage brand cards ("category"
     * key — despite the name, historically used as brand search text since
     * every product used to share the fake category "Laptops") and by the
     * category cards / header dropdown ("cat" key — a real category, now
     * meaningful since productDataService infers real categories client-side).
     * @param {Object} pageRef - LWR page reference object
     */
    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        const brand = pageRef && pageRef.state && pageRef.state.category;
        if (brand) {
            this.draftFilters = { ...this.draftFilters, search: brand };
            this.appliedFilters = { ...this.appliedFilters, search: brand };
        }

        const cat = pageRef && pageRef.state && pageRef.state.cat;
        if (cat) {
            this.draftFilters = { ...this.draftFilters, category: cat };
            this.appliedFilters = { ...this.appliedFilters, category: cat };
        }
    }

    /**
     * Builds the category dropdown options from the loaded product list.
     * Includes an "All Categories" entry at the top.
     */
    get categoryOptions() {
        const cats = extractCategories(this.allProducts).map((c) => c.name);
        return ['', ...cats].map((name) => ({
            name,
            label: name || 'All Categories',
            selected: name === this.draftFilters.category
        }));
    }

    /**
     * Builds the sort dropdown options, marking the currently selected one.
     */
    get sortOptions() {
        const options = [
            { value: 'newest', label: 'Newest' },
            { value: 'priceLow', label: 'Price: Low to High' },
            { value: 'priceHigh', label: 'Price: High to Low' }
        ];
        return options.map((o) => ({ ...o, selected: o.value === this.sortBy }));
    }

    /**
     * Applies the committed filters to allProducts, then sorts the result.
     * Returns the full filtered+sorted list (pagination is applied in pagedProducts).
     */
    get filteredProducts() {
        const f = this.appliedFilters;
        let list = this.allProducts.filter((p) => {
            if (f.search && !p.productName.toLowerCase().includes(f.search.toLowerCase())) {
                return false;
            }
            if (f.category && p.category !== f.category) {
                return false;
            }
            if (f.minPrice !== '' && p.price < Number(f.minPrice)) {
                return false;
            }
            if (f.maxPrice !== '' && p.price > Number(f.maxPrice)) {
                return false;
            }
            return true;
        });

        list = [...list];
        switch (this.sortBy) {
            case 'priceLow':
                list.sort((a, b) => a.price - b.price);
                break;
            case 'priceHigh':
                list.sort((a, b) => b.price - a.price);
                break;
            default:
                // Newest: reverse of the catalog's alphabetical base order.
                list.reverse();
        }
        return list;
    }

    /** True when the filtered list has at least one product. */
    get hasResults() {
        return this.filteredProducts.length > 0;
    }

    /** Human-readable result count label shown above the product grid. */
    get resultCountLabel() {
        const count = this.filteredProducts.length;
        return `${count} product${count === 1 ? '' : 's'} found`;
    }

    /** Total number of pages based on PAGE_SIZE and the filtered product count. */
    get totalPages() {
        return Math.max(1, Math.ceil(this.filteredProducts.length / PAGE_SIZE));
    }

    /** True when the current page is the first page (disables Prev button). */
    get isFirstPage() {
        return this.currentPage <= 1;
    }

    /** True when the current page is the last page (disables Next button). */
    get isLastPage() {
        return this.currentPage >= this.totalPages;
    }

    /**
     * Builds the numbered page button array for the pagination bar.
     * The active page gets a distinct CSS class.
     */
    get pageNumbers() {
        const pages = [];
        for (let i = 1; i <= this.totalPages; i++) {
            pages.push({ number: i, className: i === this.currentPage ? 'tb-page-btn tb-page-btn-active' : 'tb-page-btn' });
        }
        return pages;
    }

    /** True when the grid view mode is active. */
    get isGridView() { return this.viewMode === 'grid'; }
    /** True when the list view mode is active. */
    get isListView()  { return this.viewMode === 'list'; }

    /** CSS class for the grid view toggle button — active modifier when selected. */
    get gridButtonClass() {
        return this.isGridView ? 'tb-view-btn tb-view-btn-active' : 'tb-view-btn';
    }

    /** CSS class for the list view toggle button — active modifier when selected. */
    get listButtonClass() {
        return this.isListView ? 'tb-view-btn tb-view-btn-active' : 'tb-view-btn';
    }

    /**
     * Returns the current page's slice of the filtered+sorted list.
     * Each product is enriched with a display initial and the live cart quantity
     * for the list-view +/- stepper.
     */
    get pagedProducts() {
        const start = (this.currentPage - 1) * PAGE_SIZE;
        return this.filteredProducts.slice(start, start + PAGE_SIZE).map((p) => {
            const cartQuantity = getItemQuantity(p.productId);
            return {
                ...p,
                categoryInitial: p.productName.charAt(0).toUpperCase(),
                cartQuantity,
                inCart: cartQuantity > 0
            };
        });
    }

    /** Updates the search draft filter as the user types. */
    handleSearchInput(event) {
        this.draftFilters = { ...this.draftFilters, search: event.target.value };
    }

    /** Updates the category draft filter when the dropdown changes. */
    handleCategoryChange(event) {
        this.draftFilters = { ...this.draftFilters, category: event.target.value };
    }

    /** Updates the minimum price draft filter as the user types. */
    handleMinPriceInput(event) {
        this.draftFilters = { ...this.draftFilters, minPrice: event.target.value };
    }

    /** Updates the maximum price draft filter as the user types. */
    handleMaxPriceInput(event) {
        this.draftFilters = { ...this.draftFilters, maxPrice: event.target.value };
    }

    /**
     * Commits the draft filters to appliedFilters and resets to page 1.
     * Called when the user clicks "Apply Filters".
     */
    handleApplyFilters() {
        this.appliedFilters = { ...this.draftFilters };
        this.currentPage = 1;
    }

    /**
     * Resets all filters to their default empty state and returns to page 1.
     * Called when the user clicks "Clear All".
     */
    handleClearAll() {
        this.draftFilters = { ...DEFAULT_FILTERS };
        this.appliedFilters = { ...DEFAULT_FILTERS };
        this.currentPage = 1;
    }

    /** Updates the sort key and resets to page 1 when the sort dropdown changes. */
    handleSortChange(event) {
        this.sortBy = event.target.value;
        this.currentPage = 1;
    }

    /** Switches to grid view mode. */
    handleGridView() { this.viewMode = 'grid'; }
    /** Switches to list view mode. */
    handleListView() { this.viewMode = 'list'; }

    /** Decrements the current page (no-op on the first page). */
    handlePrevPage() {
        if (!this.isFirstPage) { this.currentPage -= 1; }
    }

    /** Increments the current page (no-op on the last page). */
    handleNextPage() {
        if (!this.isLastPage) { this.currentPage += 1; }
    }

    /**
     * Jumps directly to a specific page when a numbered page button is clicked.
     * @param {Event} event - currentTarget.dataset.page contains the target page number
     */
    handlePageClick(event) {
        this.currentPage = Number(event.currentTarget.dataset.page);
    }

    /**
     * Navigates to the Product Detail page when a product name is clicked in list view.
     * @param {Event} event - currentTarget.dataset.id contains the product's Salesforce Id
     */
    handleListProductClick(event) {
        this[NavigationMixin.Navigate](getProductRef(event.currentTarget.dataset.id));
    }

    /**
     * Adds a product to the cart from the list-view "Add to Cart" button.
     * @param {Event} event - currentTarget.dataset.id contains the product's Salesforce Id
     */
    handleListAddToCart(event) {
        const productId = event.currentTarget.dataset.id;
        const product = this.allProducts.find((p) => p.productId === productId);
        if (product) {
            addItem(product, 1);
            showToast(`${product.productName} added to cart.`, 'success');
        }
    }

    /**
     * Increments the cart quantity by 1 from the list-view stepper.
     * @param {Event} event - currentTarget.dataset.id contains the product's Salesforce Id
     */
    handleListIncrease(event) {
        const productId = event.currentTarget.dataset.id;
        const product = this.allProducts.find((p) => p.productId === productId);
        if (product) { addItem(product, 1); }
    }

    /**
     * Decrements the cart quantity by 1 from the list-view stepper.
     * Removes the item entirely when quantity would reach 0.
     * @param {Event} event - currentTarget.dataset.id contains the product's Salesforce Id
     */
    handleListDecrease(event) {
        const productId = event.currentTarget.dataset.id;
        const quantity = getItemQuantity(productId);
        if (quantity <= 1) {
            removeItem(productId);
        } else {
            updateQuantity(productId, quantity - 1);
        }
    }
}
