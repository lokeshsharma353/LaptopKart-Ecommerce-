import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getShopRef } from 'c/navigationService';
import LOKESH_PHOTO from '@salesforce/resourceUrl/DevLokesh';
import TANISHQ_PHOTO from '@salesforce/resourceUrl/DevTanishq';

/** Company stats shown in the stats grid section. */
const STATS = [
    { label: 'Products',        value: '500+' },
    { label: 'Happy Customers', value: '50K+' },
    { label: 'Cities Served',   value: '120+' },
    { label: 'Years Running',   value: '5+'   }
];

/** Company values shown in the values grid section. */
const VALUES = [
    { icon: '✓', title: 'Quality First',  text: 'Every product is sourced from brands we trust and stand behind — no grey-market stock, ever.' },
    { icon: '◎', title: 'Real Support',   text: 'A real person helps when something goes wrong, not just a bot and a ticket number.' },
    { icon: '⚡', title: 'Fast Delivery', text: 'Reliable next-day shipping so your order arrives exactly when promised.' }
];

/** The two developers behind LaptopKart, shown in the Meet the Developers section. */
const DEVELOPERS = [
    {
        id: 'd1',
        name: 'Lokesh Sharma',
        role: 'Developer',
        photo: LOKESH_PHOTO,
        linkedin: 'https://www.linkedin.com/in/lokesh-sharma-6728a828a?utm_source=share_via&utm_content=profile&utm_medium=member_android'
    },
    {
        id: 'd2',
        name: 'Tanishk Sirohi',
        role: 'Developer',
        photo: TANISHQ_PHOTO,
        linkedin: 'https://www.linkedin.com/in/tanishk-sirohi-a39845297?utm_source=share_via&utm_content=profile&utm_medium=member_android'
    }
];

/**
 * TechBasketAboutUs — the About Us page.
 * Sections: hero, company story, stats grid, values grid, and a Shop Now CTA.
 * Uses IntersectionObserver for scroll-reveal animations on each section.
 */
export default class TechBasketAboutUs extends NavigationMixin(LightningElement) {
    stats  = STATS;
    values = VALUES;
    developers = DEVELOPERS;

    /** Guard flag — prevents the IntersectionObserver from being set up more than once. */
    _observerInit = false;

    /**
     * Lifecycle: sets up the IntersectionObserver for scroll-reveal animations.
     * Runs only once (guarded by _observerInit) to avoid re-observing on re-renders.
     * Each element with the tb-reveal class gets the tb-visible class added when it
     * scrolls into view, triggering its CSS entrance animation.
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
        this.template.querySelectorAll('.tb-reveal').forEach(el => observer.observe(el));
        this._observer = observer;
    }

    /**
     * Lifecycle: disconnects the IntersectionObserver to prevent memory leaks
     * when the component is removed from the DOM.
     */
    disconnectedCallback() {
        if (this._observer) this._observer.disconnect();
    }

    /** Navigates to the Product Catalog page. */
    handleShopNow() {
        this[NavigationMixin.Navigate](getShopRef());
    }

    /**
     * Opens a developer's LinkedIn profile in a new tab. Uses window.open()
     * from an explicit click handler rather than a plain <a href target="_blank">,
     * since a plain anchor's external navigation can get swallowed by the LWR
     * site's own client-side router.
     * @param {Event} event - currentTarget.dataset.url contains the LinkedIn URL
     */
    handleLinkedInClick(event) {
        const url = event.currentTarget.dataset.url;
        window.open(url, '_blank', 'noopener,noreferrer');
    }
}
