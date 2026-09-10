import { LightningElement, api, track } from 'lwc';
import { loadProducts, filterBySearch } from 'c/productDataService';

/**
 * TechBasketSearch — reusable product search box with live autocomplete.
 * Preloads the full product catalog on connect so suggestions are computed
 * synchronously on every keystroke without additional Apex calls.
 * Emits two custom events for the parent to handle navigation:
 *   - "search"  { detail: { term } }     — user pressed Enter or clicked Search
 *   - "select"  { detail: { productId }} — user clicked a suggestion
 */
export default class TechBasketSearch extends LightningElement {
    /** Placeholder text shown in the search input when empty. */
    @api placeholder = 'Search products...';

    /** Current value of the search input field. */
    @track searchTerm = '';
    /** Up to 6 product suggestions matching the current search term. */
    @track suggestions = [];

    /** Full product list — preloaded once so filtering is synchronous. */
    allProducts = [];

    /**
     * Lifecycle: preloads the full product catalog from productDataService.
     * Subsequent keystrokes filter this in-memory list without hitting Apex again.
     */
    connectedCallback() {
        loadProducts().then((products) => { this.allProducts = products; });
    }

    /** True once the user has typed something — drives the suggestions dropdown visibility. */
    get showSuggestions() {
        return this.searchTerm.trim().length > 0;
    }

    /** True when there is a search term but no matching products found. */
    get noResults() {
        return this.showSuggestions && this.suggestions.length === 0;
    }

    /**
     * Updates the search term and recomputes suggestions on every keystroke.
     * Limits suggestions to 6 items to keep the dropdown compact.
     * @param {Event} event - input event from the search field
     */
    handleInput(event) {
        this.searchTerm = event.target.value;
        this.suggestions = filterBySearch(this.allProducts, this.searchTerm).slice(0, 6);
    }

    /**
     * Submits the current search term when the Enter key is pressed.
     * @param {KeyboardEvent} event - keydown event from the search field
     */
    handleKeydown(event) {
        if (event.key === 'Enter') { this.submitSearch(); }
    }

    /**
     * Fires the "search" custom event with the current term and clears the dropdown.
     * The parent (techBasketHeader) handles navigation to the catalog.
     */
    submitSearch() {
        this.dispatchEvent(new CustomEvent('search', { detail: { term: this.searchTerm } }));
        this.suggestions = [];
    }

    /**
     * Fires the "select" custom event with the chosen product id when a suggestion is clicked.
     * Clears the input and dropdown after selection.
     * @param {Event} event - currentTarget.dataset.id contains the selected product's Salesforce Id
     */
    handleSuggestionClick(event) {
        const productId = event.currentTarget.dataset.id;
        this.searchTerm = '';
        this.suggestions = [];
        this.dispatchEvent(new CustomEvent('select', { detail: { productId } }));
    }
}
