import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import signUp from '@salesforce/apex/LoginCredentialsController.signUp';
import logIn from '@salesforce/apex/LoginCredentialsController.logIn';
import requestPasswordReset from '@salesforce/apex/LoginCredentialsController.requestPasswordReset';
import getOrdersByEmail from '@salesforce/apex/CheckoutController.getOrdersByEmail';
import { getSession, setSession, clearSession, subscribe } from 'c/authService';
import { rememberEmail } from 'c/orderService';
import { getOrderConfirmationRef, getProductRef } from 'c/navigationService';
import { showToast } from 'c/toastService';
import { getAddresses, saveAddress, deleteAddress } from 'c/addressService';
import { getWishlist, toggleWishlist } from 'c/wishlistService';
import { loadProducts, findById } from 'c/productDataService';
import { getSettings, saveSettings } from 'c/accountSettingsService';
import {
    EMAIL_PATTERN, PHONE_PATTERN, NAME_PATTERN,
    EMAIL_ERROR, PHONE_ERROR, NAME_ERROR, sanitizePhoneInput
} from 'c/formValidators';
import APP_LOGO from '@salesforce/resourceUrl/AppLogo';

/**
 * TechBasketMyAccount — the Account page.
 * This storefront has no real per-shopper Salesforce login (every visitor is
 * the Site Guest User) — login/sign-up is a lightweight custom system backed
 * by the Login_Credentials__c object (see LoginCredentialsController) and a
 * client-side session (see authService). Logged out: a Log In / Sign Up
 * card. Logged in: a sidebar-driven dashboard — Profile, Order History,
 * Saved Addresses, Wishlist, Payment Methods, Reviews & Ratings, Account
 * Settings. Every section shows real data from an actual backing service
 * (Orders via CheckoutController, Addresses/Wishlist/Settings via their own
 * localStorage-backed services) — Payment Methods and Reviews have no real
 * backing system in this project, so they show an honest explanation
 * instead of made-up saved cards or reviews.
 */
export default class TechBasketMyAccount extends NavigationMixin(LightningElement) {
    /** The real LaptopKart brand logo (LK monogram + wordmark), shown on the logged-out auth card. */
    logoUrl = APP_LOGO;

    /** Current session ({ id, name, email, phone }), or null when logged out. */
    @track session = null;
    /** Which form is shown when logged out: 'login', 'signUp', or 'forgotPassword'. */
    @track mode = 'login';
    /** True while a signUp/logIn/requestPasswordReset Apex call is in flight — disables the submit button. */
    @track isSubmitting = false;
    /** Error message shown above the active form, if any. */
    @track errorMessage = '';
    /** True once the Forgot Password form has been submitted successfully — shows a confirmation instead of the form. */
    @track forgotPasswordSubmitted = false;

    /** Which dashboard section is shown when logged in. */
    @track activeSection = 'profile';

    /** This shopper's own past orders, scoped to their logged-in email. */
    @track orders = [];
    /** True while the getOrdersByEmail Apex call is in flight. */
    @track isLoadingOrders = false;

    /** Saved addresses — each toggleable into an inline edit mode. */
    @track addresses = [];

    /** Full product catalog — needed to resolve wishlisted product ids to real product details. */
    @track allProducts = [];
    /** Bumped on every wishlist change to force the wishlistProducts getter to recompute (it reads localStorage directly, which LWC can't observe on its own). */
    @track wishlistVersion = 0;

    /** Notification preferences, persisted via accountSettingsService. */
    @track settings = { emailNotifications: true, smsNotifications: false };

    /** Unsubscribe function from authService — called on disconnect. */
    _unsubscribe;

    connectedCallback() {
        this.session = getSession();
        if (this.session) {
            this.initDashboard();
        }
        this._unsubscribe = subscribe((session) => {
            this.session = session;
            if (session) {
                this.initDashboard();
            } else {
                this.orders = [];
                this.activeSection = 'profile';
            }
        });
    }

    disconnectedCallback() {
        if (this._unsubscribe) this._unsubscribe();
    }

    /** Loads everything the dashboard's sections need, once a session exists. */
    initDashboard() {
        this.loadOrders();
        this.addresses = getAddresses().map((a) => ({ ...a, editing: false }));
        this.settings = getSettings();
        loadProducts().then((products) => { this.allProducts = products; });
    }

    /** True once a session exists — drives the dashboard vs. login/sign-up forms. */
    get isLoggedIn() { return !!this.session; }
    get isLoginMode() { return !this.isLoggedIn && this.mode === 'login'; }
    get isSignUpMode() { return !this.isLoggedIn && this.mode === 'signUp'; }
    get isForgotPasswordMode() { return !this.isLoggedIn && this.mode === 'forgotPassword'; }
    get hasError() { return !!this.errorMessage; }

    get loginTabClass() { return this.mode === 'login' ? 'tb-tab tb-tab-active' : 'tb-tab'; }
    get signUpTabClass() { return this.mode === 'signUp' ? 'tb-tab tb-tab-active' : 'tb-tab'; }

    get loginButtonLabel() { return this.isSubmitting ? 'Logging in…' : 'Log In'; }
    get signUpButtonLabel() { return this.isSubmitting ? 'Creating account…' : 'Create Account'; }
    get forgotPasswordButtonLabel() { return this.isSubmitting ? 'Submitting…' : 'Submit Request'; }

    /** Switches to the Sign Up tab and clears any error from the other form. */
    handleSwitchToSignUp() { this.mode = 'signUp'; this.errorMessage = ''; }
    /** Switches to the Log In tab and clears any error from the other form. */
    handleSwitchToLogin() { this.mode = 'login'; this.errorMessage = ''; this.forgotPasswordSubmitted = false; }
    /** Switches to the Forgot Password form and clears any error from the other form. */
    handleSwitchToForgotPassword() { this.mode = 'forgotPassword'; this.errorMessage = ''; this.forgotPasswordSubmitted = false; }

    /**
     * Reads a form field's *current* value straight from the DOM rather than
     * from tracked component state. Necessary because browser autofill (a
     * saved address/password) can visibly populate an input without firing
     * the standard `input` event — relying on an oninput-synced tracked
     * property would silently submit blank values in that case even though
     * the field looks filled on screen. (Fields don't need manual resetting
     * elsewhere — the if:true/if:false template blocks around each form
     * unmount and remount their inputs fresh whenever the mode or logged-in
     * state changes, which already clears any uncontrolled value.)
     * @param {string} field - the input's data-field attribute value
     * @returns {string} the input's current value (empty string if not found)
     */
    _readField(field) {
        const el = this.template.querySelector(`[data-field="${field}"]`);
        return el ? el.value : '';
    }

    /**
     * Live-sanitizes a phone input as the shopper types: strips anything
     * that isn't a digit and caps it at 10 characters, so it's physically
     * impossible to type an 11th digit or a letter into these fields.
     * @param {Event} event - the phone input's own input event
     */
    handlePhoneInput(event) {
        event.target.value = sanitizePhoneInput(event.target.value);
    }

    /**
     * Submits the Log In form: calls LoginCredentialsController.logIn, and on
     * success starts a session via authService (which re-renders this
     * component into the logged-in dashboard).
     */
    handleLogin() {
        this.errorMessage = '';
        const email = this._readField('loginEmail').trim();
        const password = this._readField('loginPassword');

        if (!email || !password) {
            this.errorMessage = 'Please enter your email and password.';
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        this.isSubmitting = true;
        logIn({ email, password })
            .then((session) => {
                setSession(session);
                // Keeps orderService's remembered checkout email in sync with
                // whoever is actually logged in, so the standalone Order
                // History page (which looks orders up by that remembered
                // email) always agrees with My Account's own Order History
                // tab (which looks orders up by this session's email) —
                // without this they can silently diverge whenever someone
                // logs into an account whose email differs from the email
                // last used at checkout on this browser.
                rememberEmail(session.email);
                showToast(`Welcome back, ${session.name}!`, 'success');
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /**
     * Submits the Sign Up form: calls LoginCredentialsController.signUp
     * (which blocks duplicate emails server-side), and on success starts a
     * session immediately — no separate log-in step needed after signing up.
     */
    handleSignUp() {
        this.errorMessage = '';
        const name = this._readField('signUpName').trim();
        const email = this._readField('signUpEmail').trim();
        const phone = this._readField('signUpPhone').trim();
        const password = this._readField('signUpPassword');

        if (!name || !email || !phone || !password) {
            this.errorMessage = 'Please fill in all fields.';
            return;
        }
        if (!NAME_PATTERN.test(name)) {
            this.errorMessage = NAME_ERROR;
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        if (!PHONE_PATTERN.test(phone)) {
            this.errorMessage = PHONE_ERROR;
            return;
        }
        if (password.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return;
        }
        this.isSubmitting = true;
        signUp({ name, email, phone, password })
            .then((session) => {
                setSession(session);
                // See handleLogin — keeps the two Order History surfaces in sync.
                rememberEmail(session.email);
                showToast(`Welcome, ${session.name}!`, 'success');
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /**
     * Submits the Forgot Password form: calls
     * LoginCredentialsController.requestPasswordReset, which creates a Task
     * for an admin to follow up directly — there's no automated reset link
     * in this custom login system. On success, shows a confirmation instead
     * of the form.
     */
    handleForgotPasswordSubmit() {
        this.errorMessage = '';
        const email = this._readField('forgotPasswordEmail').trim();
        const phone = this._readField('forgotPasswordPhone').trim();
        const message = this._readField('forgotPasswordMessage').trim();

        if (!email) {
            this.errorMessage = 'Please enter the email on your account.';
            return;
        }
        if (!EMAIL_PATTERN.test(email)) {
            this.errorMessage = EMAIL_ERROR;
            return;
        }
        if (phone && !PHONE_PATTERN.test(phone)) {
            this.errorMessage = PHONE_ERROR;
            return;
        }
        this.isSubmitting = true;
        requestPasswordReset({ email, phone, message })
            .then(() => {
                this.forgotPasswordSubmitted = true;
            })
            .catch((error) => { this.errorMessage = this._extractError(error); })
            .finally(() => { this.isSubmitting = false; });
    }

    /** Clears the session and returns to a blank Log In form. */
    handleLogout() {
        clearSession();
        this.mode = 'login';
        this.forgotPasswordSubmitted = false;
        showToast('You have been logged out.', 'info');
    }

    /**
     * Extracts a readable message from an AuraHandledException thrown by Apex.
     * @param {Object} error - the LWC imperative Apex error object
     * @returns {string} a user-facing error message
     */
    _extractError(error) {
        if (error && error.body && error.body.message) {
            return error.body.message;
        }
        return 'Something went wrong. Please try again.';
    }

    // ───────────────────────── Dashboard sidebar ─────────────────────────

    /** Builds the sidebar navigation item array, marking the active one. */
    get navItems() {
        const items = [
            { key: 'profile', label: 'Profile' },
            { key: 'orders', label: 'Order History' },
            { key: 'addresses', label: 'Saved Addresses' },
            { key: 'wishlist', label: 'Wishlist' },
            { key: 'payments', label: 'Payment Methods' },
            { key: 'reviews', label: 'Reviews & Ratings' },
            { key: 'settings', label: 'Account Settings' }
        ];
        return items.map((i) => ({
            ...i,
            className: i.key === this.activeSection ? 'tb-nav-btn tb-nav-btn-active' : 'tb-nav-btn'
        }));
    }

    /** Switches the active dashboard section. */
    handleNavClick(event) { this.activeSection = event.currentTarget.dataset.key; }

    get isProfileSection() { return this.activeSection === 'profile'; }
    get isOrdersSection() { return this.activeSection === 'orders'; }
    get isAddressesSection() { return this.activeSection === 'addresses'; }
    get isWishlistSection() { return this.activeSection === 'wishlist'; }
    get isPaymentsSection() { return this.activeSection === 'payments'; }
    get isReviewsSection() { return this.activeSection === 'reviews'; }
    get isSettingsSection() { return this.activeSection === 'settings'; }

    // ───────────────────────── Order History ─────────────────────────

    /** Loads this shopper's own orders, scoped to their logged-in email. */
    loadOrders() {
        this.isLoadingOrders = true;
        getOrdersByEmail({ email: this.session.email })
            .then((results) => {
                this.orders = results.map((order) => ({
                    ...order,
                    statusClass: order.status === 'Cancelled'
                        ? 'tb-order-status tb-order-status-cancelled'
                        : order.status === 'Activated'
                            ? 'tb-order-status tb-order-status-done'
                            : 'tb-order-status tb-order-status-processing'
                }));
            })
            .catch(() => { this.orders = []; })
            .finally(() => { this.isLoadingOrders = false; });
    }

    /** True once at least one order has loaded for this shopper. */
    get hasOrders() { return this.orders.length > 0; }

    /**
     * Navigates to the Order Confirmation page for the clicked order.
     * @param {Event} event - currentTarget.dataset.id contains the Order Salesforce Id
     */
    handleViewOrder(event) {
        this[NavigationMixin.Navigate](getOrderConfirmationRef(event.currentTarget.dataset.id));
    }

    // ───────────────────────── Saved Addresses ─────────────────────────

    /** True once at least one address has been saved. */
    get hasAddresses() { return this.addresses.length > 0; }

    /**
     * Puts an address card into edit mode.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleEditAddress(event) {
        const id = event.currentTarget.dataset.id;
        this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, editing: true } : a));
    }

    /**
     * Persists the address edit via addressService and exits edit mode.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleDoneEditAddress(event) {
        const id = event.currentTarget.dataset.id;
        const addr = this.addresses.find((a) => a.id === id);
        if (addr && addr.phone && !PHONE_PATTERN.test(addr.phone.trim())) {
            showToast(PHONE_ERROR, 'error');
            return;
        }
        if (addr) {
            const { editing, ...toSave } = addr;
            saveAddress(toSave);
        }
        this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, editing: false } : a));
        showToast('Address saved.', 'success');
    }

    /**
     * Updates a single field within an address while it is being edited.
     * Phone is sanitized live (digits only, capped at 10) the same way every
     * other phone field on the site is.
     * @param {Event} event - currentTarget.dataset.id and dataset.field identify the target
     */
    handleAddressInput(event) {
        const { id, field } = event.currentTarget.dataset;
        let value = event.target.value;
        if (field === 'phone') {
            value = sanitizePhoneInput(value);
            event.target.value = value;
        }
        this.addresses = this.addresses.map((a) => (a.id === id ? { ...a, [field]: value } : a));
    }

    /**
     * Removes an address from addressService and the displayed list.
     * @param {Event} event - currentTarget.dataset.id contains the address id
     */
    handleDeleteAddress(event) {
        const id = event.currentTarget.dataset.id;
        deleteAddress(id);
        this.addresses = this.addresses.filter((a) => a.id !== id);
        showToast('Address removed.', 'info');
    }

    /** Adds a new blank address card in edit mode — persisted once "Done" is clicked. */
    handleAddAddress() {
        const id = `addr_${Date.now()}`;
        this.addresses = [...this.addresses, { id, line1: '', city: '', phone: '', editing: true }];
    }

    // ───────────────────────── Wishlist ─────────────────────────

    /** Returns full product objects for every wishlisted product id. */
    get wishlistProducts() {
        // eslint-disable-next-line no-unused-expressions
        this.wishlistVersion; // declares reactivity on this tracked counter
        return getWishlist()
            .map((id) => findById(this.allProducts, id))
            .filter((p) => p !== null);
    }

    /** True when the wishlist has at least one product. */
    get hasWishlistItems() { return this.wishlistProducts.length > 0; }

    /**
     * Removes a product from the wishlist.
     * @param {Event} event - currentTarget.dataset.id contains the product id
     */
    handleRemoveWishlistItem(event) {
        toggleWishlist(event.currentTarget.dataset.id);
        this.wishlistVersion += 1;
        showToast('Removed from wishlist.', 'info');
    }

    /**
     * Navigates to the Product Detail page for a wishlisted product.
     * @param {Event} event - currentTarget.dataset.id contains the product id
     */
    handleViewWishlistProduct(event) {
        this[NavigationMixin.Navigate](getProductRef(event.currentTarget.dataset.id));
    }

    // ───────────────────────── Account Settings ─────────────────────────

    /**
     * Updates a notification setting when its checkbox changes.
     * @param {Event} event - target.dataset.field and target.checked
     */
    handleSettingChange(event) {
        const field = event.target.dataset.field;
        this.settings = { ...this.settings, [field]: event.target.checked };
    }

    /** Persists notification settings via accountSettingsService. */
    handleSaveSettings() {
        saveSettings(this.settings);
        showToast('Settings saved.', 'success');
    }
}
