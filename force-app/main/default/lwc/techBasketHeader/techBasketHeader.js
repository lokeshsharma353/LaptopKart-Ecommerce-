import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import {
    getHomeRef, getShopRef, getShopRefByCategory, getAccountRef, getContactRef,
    getProductRef, getAboutRef, getCartRef, getLoginRef, getSignUpRef
} from 'c/navigationService';
import { getCartCount, subscribe } from 'c/cartService';
import { getCategories } from 'c/categoryService';
import { getTheme, toggleTheme, subscribe as subscribeTheme } from 'c/themeService';
import APP_LOGO from '@salesforce/resourceUrl/AppLogo';

export default class TechBasketHeader extends NavigationMixin(LightningElement) {
    @api hideSearch = false;
    @api hideCart = false;

    /** The real LaptopKart brand logo (LK monogram + wordmark), used across the header and drawer. */
    logoUrl = APP_LOGO;
    @track cartCount = 0;
    @track drawerOpen = false;
    @track searchOpen = false;
    @track isDarkTheme = false;
    @track miniCartOpen = false;

    /** Category list for the "Shop" nav item's hover dropdown. */
    categories = getCategories();

    unsubscribeCart;
    unsubscribeTheme;

    connectedCallback() {
        this.cartCount = getCartCount();
        this.unsubscribeCart = subscribe((items) => {
            this.cartCount = items.reduce((sum, i) => sum + i.quantity, 0);
        });

        this.isDarkTheme = getTheme() === 'dark';
        this.unsubscribeTheme = subscribeTheme((theme) => {
            this.isDarkTheme = theme === 'dark';
        });
    }

    disconnectedCallback() {
        if (this.unsubscribeCart) this.unsubscribeCart();
        if (this.unsubscribeTheme) this.unsubscribeTheme();
    }

    get showCart()     { return !this.hideCart; }
    get hasCartItems() { return this.cartCount > 0; }

    get themeToggleIcon()  { return this.isDarkTheme ? '' : ''; }
    get themeToggleLabel() { return this.isDarkTheme ? 'Switch to light mode' : 'Switch to dark mode'; }
    get themeToggleClass() {
        return this.isDarkTheme ? 'tb-theme-toggle tb-theme-toggle-active' : 'tb-theme-toggle';
    }
    get themeToggleMobileClass() {
        return this.isDarkTheme
            ? 'tb-theme-toggle tb-theme-toggle-mobile tb-theme-toggle-active'
            : 'tb-theme-toggle tb-theme-toggle-mobile';
    }

    handleToggleTheme() { toggleTheme(); }

    get hamburgerLine1() { return this.drawerOpen ? 'tb-hline tb-hline-open1' : 'tb-hline'; }
    get hamburgerLine2() { return this.drawerOpen ? 'tb-hline tb-hline-open2' : 'tb-hline'; }
    get hamburgerLine3() { return this.drawerOpen ? 'tb-hline tb-hline-open3' : 'tb-hline'; }

    toggleSearch()  { this.searchOpen = !this.searchOpen; }
    toggleDrawer()  { this.drawerOpen = !this.drawerOpen; }
    closeDrawer()   { this.drawerOpen = false; }
    handleLogout()  { window.location.href = '/secur/logout.jsp'; }

    handleSearch(event) {
        this.searchOpen = false;
        const term = (event && event.detail && event.detail.term) || '';
        this[NavigationMixin.Navigate](getShopRef(term || undefined));
    }
    handleSearchSelect(event)   { this.searchOpen = false; this[NavigationMixin.Navigate](getProductRef(event.detail.productId)); }

    goHome()    { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getHomeRef()); }
    goShop()    { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getShopRef()); }

    /**
     * Navigates to the catalog pre-filtered by the clicked category, from
     * the "Shop" nav item's hover dropdown.
     * @param {Event} event - currentTarget.dataset.category contains the category name
     */
    goCategory(event) {
        this.drawerOpen = false;
        this.searchOpen = false;
        this[NavigationMixin.Navigate](getShopRefByCategory(event.currentTarget.dataset.category));
    }
    goAbout()   { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getAboutRef()); }
    goAccount() { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getAccountRef()); }
    goContact() { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getContactRef()); }
    goCart()    { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getCartRef()); }

    /** Opens the mini-cart drawer instead of navigating away — used by the header's cart icon. */
    openMiniCart() { this.drawerOpen = false; this.searchOpen = false; this.miniCartOpen = true; }
    /** Closes the mini-cart drawer, fired by its close event. */
    closeMiniCart() { this.miniCartOpen = false; }
    goLogin()   { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getLoginRef()); }
    goSignUp()  { this.drawerOpen = false; this.searchOpen = false; this[NavigationMixin.Navigate](getSignUpRef()); }
}