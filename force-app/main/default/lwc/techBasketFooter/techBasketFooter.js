import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    getHomeRef,
    getShopRef,
    getContactRef,
    getAccountRef,
    getOrderTrackingRef,
    getAboutRef
} from 'c/navigationService';
import APP_LOGO from '@salesforce/resourceUrl/AppLogo';

/**
 * TechBasketFooter — site-wide bottom footer.
 * Renders the brand logo, quick links, customer service links, social icons,
 * and a dynamic copyright year.
 */
export default class TechBasketFooter extends NavigationMixin(LightningElement) {

    /** The real LaptopKart brand logo (LK monogram + wordmark). */
    logoUrl = APP_LOGO;

    /** Returns the current calendar year for the copyright notice. */
    get currentYear() {
        return new Date().getFullYear();
    }

    /** Navigates to the Home page. */
    goHome() {
        this[NavigationMixin.Navigate](getHomeRef());
    }

    /** Navigates to the Product Catalog (Shop) page. */
    goShop() {
        this[NavigationMixin.Navigate](getShopRef());
    }

    /** Navigates to the About Us page. */
    goAbout() {
        this[NavigationMixin.Navigate](getAboutRef());
    }

    /** Navigates to the Contact Us page. */
    goContact() {
        this[NavigationMixin.Navigate](getContactRef());
    }

    /** Navigates to the My Account page. */
    goAccount() {
        this[NavigationMixin.Navigate](getAccountRef());
    }

    /** Navigates to the Order Tracking page (no specific order pre-selected). */
    goOrderTracking() {
        this[NavigationMixin.Navigate](getOrderTrackingRef());
    }
}
