import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getShopRef, getShopRefByCategory, getAboutRef } from 'c/navigationService';
import { loadProducts } from 'c/productDataService';
import { showToast } from 'c/toastService';
import { getCategories } from 'c/categoryService';
import { EMAIL_PATTERN, EMAIL_ERROR } from 'c/formValidators';
import TBIMAGES from '@salesforce/resourceUrl/tbimages';

/** Static testimonial data — real reviews would come from a Salesforce object. */
const TESTIMONIALS = [
    { id: 't1', name: 'Lokesh Sharma', initial: 'P', product: 'MacBook Pro 14"', quote: 'Absolutely stunning machine. LaptopKart delivered it the very next day. Packaging was immaculate.' },
    { id: 't2', name: 'Rahul Mehta',  initial: 'R', product: 'Dell XPS 15',     quote: 'Best price I found anywhere online. Laptop is exactly as described. Will definitely buy again.' },
    { id: 't3', name: 'Ananya Kapoor',initial: 'A', product: 'HP Spectre x360', quote: 'Support team helped me pick the right model. Arrived in 24 hours. Highly recommend.' }
];

/**
 * All six laptop brands the storefront actually carries inventory for
 * (ProductCatalogController.LAPTOP_BRANDS), shown in the brand selector
 * grid — must stay in sync with brandService's BRANDS list (the source of
 * truth for product image matching). logoUrl is unused dead data (the
 * template only renders brand.name as text; external logo images were
 * tried and abandoned earlier), kept only because removing it isn't part
 * of this fix.
 */
const BRANDS = [
    { id: 'b1', name: 'Apple',  logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/f/fa/Apple_logo_black.svg' },
    { id: 'b2', name: 'Dell',   logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/4/48/Dell_Logo.svg' },
    { id: 'b3', name: 'HP',     logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/a/ad/HP_logo_2012.svg' },
    { id: 'b4', name: 'Lenovo', logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/b/b8/Lenovo_logo_2015.svg' },
    { id: 'b5', name: 'ASUS',   logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/2/2e/ASUS_Logo.svg' },
    { id: 'b6', name: 'Acer',   logoUrl: 'https://upload.wikimedia.org/wikipedia/commons/0/00/Acer_2011.svg' }
];

/**
 * Hero background image filenames from the tbimages static resource zip.
 * The first PRIORITY_COUNT entries always lead the slideshow in this exact
 * order (Herobg10, Herobg8, herobg1); everything after that is shuffled.
 */
const ALL_HERO_FILES = [
    'Herobg10.avif',
    'Herobg8.avif',
    'herobg1.jpg',
    'Hero bg11.avif',
    'hero1.jpg',
    'hero3.jpg',
    'hero4.jpg',
    'herobg2.jpg',
    'herobg7.jpg',
    'herobg9.jpg',
    'Herobg12.avif',
    'Herobg13.avif'
];
const PRIORITY_COUNT = 3;

/**
 * Curated "Top Picks This Week" lineup, shown in this exact order as a
 * single row — a fixed hand-picked list rather than the first N products
 * off the catalog.
 */
const TOP_PICKS = [
    'Acer Predator Helios Neo 16',
    'Asus TUF Gaming A15',
    'Apple MacBook Air 15 M2',
    'HP Victus 15',
    'Samsung Galaxy Book3'
];

/**
 * Fisher-Yates shuffle — randomises order.
 * @param {Array} arr - array to shuffle
 * @returns {Array} new shuffled array (original is not mutated)
 */
function shuffle(arr) {
    const a = [...arr];
    for (let i = a.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
}

/**
 * Builds the hero slideshow order: the priority images first, in their
 * fixed order, followed by the rest of the pool shuffled randomly.
 * @returns {Array} ordered array of hero image filenames
 */
function buildHeroOrder() {
    const priority = ALL_HERO_FILES.slice(0, PRIORITY_COUNT);
    const rest = shuffle(ALL_HERO_FILES.slice(PRIORITY_COUNT));
    return [...priority, ...rest];
}

/**
 * TechBasketHome — the LaptopKart homepage.
 * Sections: Ken Burns hero slideshow, stats bar, brand selector,
 * featured products grid, "Why LaptopKart" cards, testimonials, newsletter.
 */
export default class TechBasketHome extends NavigationMixin(LightningElement) {
    /** Products shown in the "Top Picks" featured grid (first 8 from catalog). */
    @track featuredProducts = [];
    /** True while the Apex product call is in flight. */
    @track isLoading = true;
    /** Currently highlighted brand in the brand selector grid. */
    @track selectedBrand = '';
    /** Newsletter email input value. */
    @track email = '';
    /** Validation error message for the newsletter email field. */
    @track emailError = '';
    /** True after a successful newsletter subscription. */
    @track subscribed = false;
    /** Index of the currently visible hero slide (0-based). */
    @track currentSlide = 0;

    testimonials = TESTIMONIALS;
    categories = getCategories();
    /** Hero image filenames in slideshow order, set once at component creation. */
    _heroFiles = buildHeroOrder();
    /** Reference to the setInterval timer so it can be cleared on disconnect. */
    _slideInterval;

    /**
     * Builds the slide objects for the hero section.
     * All slides are mounted in the DOM simultaneously; only the active one
     * has the tb-slide-active class, which restarts the Ken Burns CSS animation.
     */
    get heroSlides() {
        return this._heroFiles.map((f, i) => ({
            id: i,
            style: `background-image: url('${TBIMAGES}/${encodeURIComponent(f)}');`,
            cls: i === this.currentSlide ? 'tb-slide tb-slide-active' : 'tb-slide'
        }));
    }

    /**
     * A single static, blurred hero1.jpg background used ONLY on mobile
     * (see .tb-hero-mobile-bg in CSS) instead of the full Ken Burns
     * slideshow — a calmer, more deliberate "premium" look on a small
     * screen rather than several images cycling through it.
     */
    get mobileHeroStyle() {
        return `background-image: url('${TBIMAGES}/hero1.jpg');`;
    }

    /**
     * Builds the dot indicator objects for the hero slideshow.
     * The active dot gets a distinct style to show which slide is current.
     */
    get slideDots() {
        return this._heroFiles.map((_, i) => ({
            id: i,
            cls: i === this.currentSlide ? 'tb-dot tb-dot-active' : 'tb-dot'
        }));
    }

    /**
     * Returns the brand list with an active CSS class applied to the selected brand.
     * Used by the brand selector grid to highlight the chosen brand card.
     */
    get brands() {
        return BRANDS.map(b => ({
            ...b,
            cardClass: this.selectedBrand === b.name ? 'tb-brand-card tb-brand-card-active' : 'tb-brand-card'
        }));
    }

    /**
     * Lifecycle: loads the curated Top Picks lineup and starts the hero
     * slideshow timer. featuredProducts is built from TOP_PICKS, in that
     * exact order — not just the first N products off the catalog.
     */
    connectedCallback() {
        loadProducts()
            .then((products) => {
                const byName = new Map(products.map((p) => [p.productName.toLowerCase(), p]));
                this.featuredProducts = TOP_PICKS
                    .map((name) => byName.get(name.toLowerCase()))
                    .filter(Boolean);
                this.isLoading = false;
            })
            .catch(() => { this.isLoading = false; });

        // Advances the hero slide every 6 seconds.
        this._slideInterval = setInterval(() => {
            this.currentSlide = (this.currentSlide + 1) % this._heroFiles.length;
        }, 6000);
    }

    /**
     * Lifecycle: sets up the IntersectionObserver for scroll-reveal animations.
     * Runs only once (guarded by _observerInit) to avoid re-observing on re-renders.
     */
    renderedCallback() {
        if (this._observerInit) return;
        this._observerInit = true;
        const observer = new IntersectionObserver((entries) => {
            entries.forEach(e => {
                if (e.isIntersecting) {
                    e.target.classList.add('tb-visible');
                    observer.unobserve(e.target); // stop watching once revealed
                }
            });
        }, { threshold: 0.15 });
        this.template.querySelectorAll('.tb-reveal, .tb-testimonial-card').forEach(el => observer.observe(el));
        this._observer = observer;
    }

    /**
     * Lifecycle: clears the slide interval and disconnects the IntersectionObserver
     * to prevent memory leaks when the component is removed from the DOM.
     */
    disconnectedCallback() {
        if (this._slideInterval) clearInterval(this._slideInterval);
        if (this._observer) this._observer.disconnect();
    }

    /** Navigates to the Product Catalog page. */
    handleShopNow()   { this[NavigationMixin.Navigate](getShopRef()); }
    /** Navigates to the About Us page. */
    handleLearnMore() { this[NavigationMixin.Navigate](getAboutRef()); }
    /** Navigates to the Product Catalog page (used by the "Search Laptops" hero button). */
    handleGoSearch()  { this[NavigationMixin.Navigate](getShopRef()); }

    /**
     * Handles a brand card click in the brand selector grid.
     * Toggles the selection off if the same brand is clicked again,
     * then navigates to the catalog with the brand name as a search filter.
     * @param {Event} event - currentTarget.dataset.brand contains the brand name
     */
    handleBrandSelect(event) {
        const brand = event.currentTarget.dataset.brand;
        this.selectedBrand = this.selectedBrand === brand ? '' : brand;
        this[NavigationMixin.Navigate](getShopRef(brand));
    }

    /**
     * Handles a category card click — navigates to the catalog pre-filtered
     * by that real (client-inferred) category.
     * @param {Event} event - currentTarget.dataset.category contains the category name
     */
    handleCategorySelect(event) {
        const category = event.currentTarget.dataset.category;
        this[NavigationMixin.Navigate](getShopRefByCategory(category));
    }

    /**
     * Updates the newsletter email field and clears any previous error or success state.
     * @param {Event} event - input event from the email field
     */
    handleEmailInput(event) {
        this.email = event.target.value;
        this.emailError = '';
        this.subscribed = false;
    }

    /**
     * Validates the newsletter email and shows a success toast if valid.
     * Shows an inline error message if the email format is invalid.
     */
    handleSubscribe() {
        if (!EMAIL_PATTERN.test(this.email)) {
            this.emailError = EMAIL_ERROR;
            return;
        }
        this.subscribed = true;
        this.email = '';
        showToast('Thanks for subscribing!', 'success');
    }
}
